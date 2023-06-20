export const gc = (edges) => { gc_manager.run(edges, Ruby.get_exported_imported()) }
export const eager_gc = (edges) => { gc_manager.run_with_gc(edges, Ruby.get_exported_imported()) }

let has_not_override = true

export const gc_manager = new class {
    run(edges_json, exported_and_imported) {
        const edges = JSON.parse(edges_json)
        const [exported, imported] = exported_and_imported
        this.repair_previous_gc_effects(exported, imported)
        const rootset = this.get_root_set(edges, exported)
        this.check_liveness(edges, exported, imported)
        this.unlink_exported_objects(exported, rootset)
        if (has_not_override) {
            has_not_override = false
            this.override_methods(exported)
        }
    }

    run_with_gc(edges_json, exported_and_imported) {
        const edges = JSON.parse(edges_json)
        const [exported, imported] = exported_and_imported
        const rootset = this.get_root_set(edges, exported)
        this.check_liveness(edges, exported, imported)
        this.unlink_exported_objects(exported, rootset)
        globalThis.gc()     // needs --expose-gc
        this.repair_previous_gc_effects(exported, imported)
    }

    // returns the references that are exported to Ruby and are reachable
    // from the Ruby's root set.
    get_root_set(edges, exported) {
        const num_exported = exported.objects.length
        const rootset = Array(num_exported).fill(false)
        for (const idx of edges['root'])
            rootset[idx] = true
        return rootset
    }

    check_liveness(edges, exported, imported) {
        const imported_objs = imported.objects
        const exported_objs = exported.objects
        for (const from_idx in edges)
            if (from_idx !== 'root') {
                const prref = imported_objs[from_idx].deref()
                if (prref != undefined) {
                    const rref = prref.__self__
                    const to_indexes = edges[from_idx]
                    rref.to_indexes = to_indexes
                    rref.to_objs = to_indexes.map(idx => exported_objs[idx])
                }
            }
    }

    unlink_exported_objects(exported, rootset) {
        const exported_objs = exported.objects
        const htable = exported.hashtable
        const unlinked_objs = new WeakMap()
        for (let i = 0; i < exported_objs.length; i++)
            if (!rootset[i]) {
                const obj = exported_objs[i]
                if (obj !== null && typeof obj !== 'number') {
                    unlinked_objs.set(obj, i)
                    htable.delete(obj)
                    exported_objs[i] = null
                }
            }
        // unlinked_objects would be deprecated later since the index
        // for an exported object may be reused.
        exported.unlinked_objects = unlinked_objs
    }

    repair_previous_gc_effects(exported, imported) {
        for (const wref of imported.objects)
            if (wref) {
                const prref = wref.deref()
                if (prref != undefined) {
                    const rref = prref.__self__
                    this.repair_hidden_references_from_remoteref(rref, exported)
                }
            }

        exported.unlinked_objects = null
    }

    repair_hidden_references_from_remoteref(rref, exported) {
        const exported_objs = exported.objects
        if (rref.to_indexes) {
            rref.to_indexes.forEach((to_idx, i) => {
                const obj = rref.to_objs[i]
                if (exported_objs[to_idx] === null) {
                    exported_objs[to_idx] = obj
                    exported.hashtable.set(obj, to_idx)
                }
                else {
                    // exported_objs[to_idx] is not null when it has been
                    // already restored.  It must be equal to obj since
                    // to_idx is not reused until rref is reclaimed.
                    if (exported_objs[to_idx] !== obj)
                        throw `broken export index: ${to_idx}`
                }
            })
            rref.to_indexes = null
            rref.to_objs = null
        }
    }

    override_methods(exported) {
        exported.find_unlinked_obj = function (obj) {
            const idx = this.unlinked_objects.get(obj)
            if (idx === undefined)
                return undefined
            else {
                const obj_at_idx = this.objects[idx]
                this.unlinked_objects.delete(obj)
                if (obj_at_idx === null) {
                    this.objects[idx] = obj
                    this.hashtable.set(obj, idx)
                    return idx
                }
                else if (obj === obj_at_idx)
                    return idx
                else
                    return undefined    // already reused
            }
        }

        exported.export = function (obj) {
            const idx = this.find_unlinked_obj(obj)
            if (idx !== undefined)
                return idx
            else {
                const idx = this.hashtable.get(obj)
                if (idx !== undefined)
                    return idx
                else {
                    const idx = this.next_element()
                    this.objects[idx] = obj
                    this.hashtable.set(obj, idx)
                    return idx
                }
            }
        }

        exported.export_remoteref = function (rref) {
            gc_manager.repair_hidden_references_from_remoteref(rref, this)
            return rref.id
        }
    }
}

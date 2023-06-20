// This benchmark is derived from havlak.rb and havlak.js
// in Stefan Marr's "Are We Fast Yet?" benchmark.
//   https://github.com/smarr/are-we-fast-yet
//
// Control flow graphs are created in Ruby and loop detection is
// executed in JavaScript.

// Adapted based on SOM and Java benchmark.
//  Copyright 2011 Google Inc.
//
//      Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//      You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//      See the License for the specific language governing permissions and
//          limitations under the License.
'use strict';

import * as som from "./som.mjs"

export async function benchmark(
    numDummyLoops, findLoopIterations,
    parLoops, pparLoops, ppparLoops) {
  var app = new LoopTesterApp();
  await app.init();
  return await app.main(
    numDummyLoops, findLoopIterations,
    parLoops, pparLoops, ppparLoops
  );
}

function UnionFindNode() { /* no op */ }

// Initialize this node.
UnionFindNode.prototype.initNode = function (bb, dfsNumber) {
  this.parent     = this;
  this.bb         = bb;
  this.dfsNumber  = dfsNumber;
  this.loop       = null;
};

// Union/Find Algorithm - The find routine.
//
// Implemented with Path Compression (inner loops are only
// visited and collapsed once, however, deep nests would still
// result in significant traversals).
//
UnionFindNode.prototype.findSet = function () {
  var nodeList = new som.Vector(),
    node = this,
    that = this;
  while (node !== node.parent) {
    if (node.parent !== node.parent.parent) {
      nodeList.append(node);
    }
    node = node.parent;
  }

  // Path Compression, all nodes' parents point to the 1st level parent.
  nodeList.forEach(function (iter) { iter.union(that.parent); });
  return node;
};

// Union/Find Algorithm - The union routine.
//
// Trivial. Assigning parent pointer is enough,
// we rely on path compression.
//
UnionFindNode.prototype.union = function (basicBlock) {
  this.parent = basicBlock;
};

// Getters/Setters
//
UnionFindNode.prototype.getBb = function () {
  return this.bb;
};

UnionFindNode.prototype.getLoop = function () {
  return this.loop;
};

UnionFindNode.prototype.getDfsNumber = function () {
  return this.dfsNumber;
};

UnionFindNode.prototype.setLoop = function (loop) {
  this.loop = loop;
};

function LoopTesterApp() {}

LoopTesterApp.prototype.init = async function () {
  this.cfg = await (await Ruby.exec('ControlFlowGraph')).new();
  this.lsg = await (await Ruby.exec('LoopStructureGraph')).new();
  await this.cfg.create_node(0);
}

// Create 4 basic blocks, corresponding to and if/then/else clause
// with a CFG that looks like a diamond
LoopTesterApp.prototype.buildDiamond = async function (start) {
  var bb0 = start;
  await (await Ruby.exec('BasicBlockEdge')).new(this.cfg, bb0, bb0 + 1);
  await (await Ruby.exec('BasicBlockEdge')).new(this.cfg, bb0, bb0 + 2);
  await (await Ruby.exec('BasicBlockEdge')).new(this.cfg, bb0 + 1, bb0 + 3);
  await (await Ruby.exec('BasicBlockEdge')).new(this.cfg, bb0 + 2, bb0 + 3);

  return bb0 + 3;
};

// Connect two existing nodes
LoopTesterApp.prototype.buildConnect = async function (start, end) {
  await (await Ruby.exec('BasicBlockEdge')).new(this.cfg, start, end);
};

// Form a straight connected sequence of n basic blocks
LoopTesterApp.prototype.buildStraight = async function (start, n) {
  for (var i = 0; i < n; i++) {
    await this.buildConnect(start + i, start + i + 1);
  }
  return start + n;
};

// Construct a simple loop with two diamonds in it
LoopTesterApp.prototype.buildBaseLoop = async function (from) {
  var header = await this.buildStraight(from, 1),
    diamond1 = await this.buildDiamond(header),
    d11      = await this.buildStraight(diamond1, 1),
    diamond2 = await this.buildDiamond(d11),
    footer   = await this.buildStraight(diamond2, 1);
  await this.buildConnect(diamond2, d11);
  await this.buildConnect(diamond1, header);

  await this.buildConnect(footer, from);
  footer = await this.buildStraight(footer, 1);
  return footer;
};

LoopTesterApp.prototype.main = async function (numDummyLoops, findLoopIterations,
                                         parLoops, pparLoops, ppparLoops) {
  await this.constructSimpleCFG();
  await this.addDummyLoops(numDummyLoops);
  await this.constructCFG(parLoops, pparLoops, ppparLoops);

  // Performing Loop Recognition, 1 Iteration, then findLoopIteration
  await this.findLoops(this.lsg);
  for (var i = 0; i < findLoopIterations; i++) {
    await this.findLoops(await (await Ruby.exec('LoopStructureGraph')).new());
  }

  await this.lsg.calculate_nesting_level();
  return [await this.lsg.num_loops(), await this.cfg.num_nodes()];
};

LoopTesterApp.prototype.constructCFG = async function (parLoops, pparLoops, ppparLoops) {
  var n = 2;

  for (var parlooptrees = 0; parlooptrees < parLoops; parlooptrees++) {
    await this.cfg.create_node(n + 1);
    await this.buildConnect(2, n + 1);
    n += 1;

    for (var i = 0; i < pparLoops; i++) {
      var top = n;
      n = await this.buildStraight(n, 1);
      for (var j = 0; j < ppparLoops; j++) {
        n = await this.buildBaseLoop(n);
      }
      var bottom = await this.buildStraight(n, 1);
      await this.buildConnect(n, top);
      n = bottom;
    }
    await this.buildConnect(n, 1);
  }
};

LoopTesterApp.prototype.addDummyLoops = async function (numDummyLoops) {
  for (var dummyloop = 0; dummyloop < numDummyLoops; dummyloop++) {
    await this.findLoops(this.lsg);
  }
};

LoopTesterApp.prototype.findLoops = async function (loopStructure) {
  var finder = new HavlakLoopFinder(this.cfg, loopStructure);
  await finder.findLoops();
};

LoopTesterApp.prototype.constructSimpleCFG = async function () {
  await this.cfg.create_node(0);
  await this.buildBaseLoop(0);
  await this.cfg.create_node(1);
  await (await Ruby.exec('BasicBlockEdge')).new(this.cfg, 0, 2);
};

var UNVISITED = 2147483647,       // Marker for uninitialized nodes.
  MAXNONBACKPREDS = (32 * 1024);  // Safeguard against pathological algorithm behavior.

function HavlakLoopFinder(cfg, lsg) {
  this.nonBackPreds = new som.Vector();
  this.backPreds  = new som.Vector();
  this.number = new som.IdentityDictionary();
  this.maxSize = 0;

  this.cfg = cfg;
  this.lsg = lsg;
}

// As described in the paper, determine whether a node 'w' is a
// "true" ancestor for node 'v'.
//
// Dominance can be tested quickly using a pre-order trick
// for depth-first spanning trees. This is why DFS is the first
// thing we run below.
HavlakLoopFinder.prototype.isAncestor = function (w, v) {
  return w <= v && v <= this.last[w];
};

// DFS - Depth-First-Search
//
// DESCRIPTION:
// Simple depth first traversal along out edges with node numbering.
HavlakLoopFinder.prototype.doDFS = async function (currentNode, current) {
  this.nodes[current].initNode(currentNode, current);
  await this.number.atPutForRubyObj(currentNode, current);

  var lastId = current,
    outerBlocks = await currentNode.out_edges();

  for (var i = 0; i < await outerBlocks.size(); i++) {
    var target = await outerBlocks.at(i);
    if (await this.number.atForRubyObj(target) == UNVISITED) {
      lastId = await this.doDFS(target, lastId + 1);
    }
  }

  this.last[current] = lastId;
  return lastId;
};

HavlakLoopFinder.prototype.initAllNodes = async function () {
  // Step a:
  //   - initialize all nodes as unvisited.
  //   - depth-first traversal and numbering.
  //   - unreached BB's are marked as dead.
  //
  var that = this;
  await (await this.cfg.get_basic_blocks()).apply(
    async function (bb) { await that.number.atPutForRubyObj(bb, UNVISITED); });
  await this.doDFS(await this.cfg.get_start_basic_block(), 0);
};

HavlakLoopFinder.prototype.identifyEdges = async function (size) {
  // Step b:
  //   - iterate over all nodes.
  //
  //   A backedge comes from a descendant in the DFS tree, and non-backedges
  //   from non-descendants (following Tarjan).
  //
  //   - check incoming edges 'v' and add them to either
  //     - the list of backedges (backPreds) or
  //     - the list of non-backedges (nonBackPreds)
  for (var w = 0; w < size; w++) {
    this.header[w] = 0;
    this.type[w] = "BB_NONHEADER";

    var nodeW = this.nodes[w].getBb();
    if (!nodeW) {
      this.type[w] = "BB_DEAD";
    } else {
      await this.processEdges(nodeW, w);
    }
  }
};

HavlakLoopFinder.prototype.processEdges = async function (nodeW, w) {
  var that = this;

  if ((await nodeW.num_pred()) > 0) {
    await (await nodeW.in_edges()).apply(async function (nodeV) {
      var v = await that.number.atForRubyObj(nodeV);
      if (v != UNVISITED) {
        if (that.isAncestor(w, v)) {
          that.backPreds.at(w).append(v);
        } else {
          that.nonBackPreds.at(w).add(v);
        }
      }
    });
  }
};

// Find loops and build loop forest using Havlak's algorithm, which
// is derived from Tarjan. Variable names and step numbering has
// been chosen to be identical to the nomenclature in Havlak's
// paper (which, in turn, is similar to the one used by Tarjan).
HavlakLoopFinder.prototype.findLoops = async function () {
  if (!(await this.cfg.get_start_basic_block())) {
    return;
  }

  var size = await this.cfg.num_nodes();

  this.nonBackPreds.removeAll();
  this.backPreds.removeAll();
  this.number.removeAll();
  if (size > this.maxSize) {
    this.header  = new Array(size);
    this.type    = new Array(size);
    this.last    = new Array(size);
    this.nodes   = new Array(size);
    this.maxSize = size;
  }

  for (var i = 0; i < size; ++i) {
    this.nonBackPreds.append(new som.Set());
    this.backPreds.append(new som.Vector());
    this.nodes[i] = new UnionFindNode();
  }

  await this.initAllNodes();
  await this.identifyEdges(size);

  // Start node is root of all other loops.
  this.header[0] = 0;

  // Step c:
  //
  // The outer loop, unchanged from Tarjan. It does nothing except
  // for those nodes which are the destinations of backedges.
  // For a header node w, we chase backward from the sources of the
  // backedges adding nodes to the set P, representing the body of
  // the loop headed by w.
  //
  // By running through the nodes in reverse of the DFST preorder,
  // we ensure that inner loop headers will be processed before the
  // headers for surrounding loops.
  //
  for (var w = size - 1; w >= 0; w--) {
    // this is 'P' in Havlak's paper
    var nodePool = new som.Vector();

    var nodeW = this.nodes[w].getBb();
    if (nodeW) {
      this.stepD(w, nodePool);

      // Copy nodePool to workList.
      var workList = new som.Vector();
      nodePool.forEach(function (niter) { workList.append(niter); });

      if (nodePool.size() !== 0) {
        this.type[w] = "BB_REDUCIBLE";
      }

      // work the list...
      while (!workList.isEmpty()) {
        var x = workList.removeFirst();

        // Step e:
        //
        // Step e represents the main difference from Tarjan's method.
        // Chasing upwards from the sources of a node w's backedges. If
        // there is a node y' that is not a descendant of w, w is marked
        // the header of an irreducible loop, there is another entry
        // into this loop that avoids w.

        // The algorithm has degenerated. Break and
        // return in this case.
        var nonBackSize = this.nonBackPreds.at(x.getDfsNumber()).size();
        if (nonBackSize > MAXNONBACKPREDS) {
          return;
        }
        this.stepEProcessNonBackPreds(w, nodePool, workList, x);
      }

      // Collapse/Unionize nodes in a SCC to a single node
      // For every SCC found, create a loop descriptor and link it in.
      //
      if ((nodePool.size() > 0) || (this.type[w] === "BB_SELF")) {
        var loop = await this.lsg.create_new_loop(nodeW, this.type[w] !== "BB_IRREDUCIBLE");
        await this.setLoopAttributes(w, nodePool, loop);
      }
    }
  }  // Step c
};  // findLoops

HavlakLoopFinder.prototype.stepEProcessNonBackPreds = function (w, nodePool,
                                                                workList, x) {
  var that = this;
  this.nonBackPreds.at(x.getDfsNumber()).forEach(function (iter) {
    var y = that.nodes[iter],
      ydash = y.findSet();

    if (!that.isAncestor(w, ydash.getDfsNumber())) {
      that.type[w] = "BB_IRREDUCIBLE";
      that.nonBackPreds.at(w).add(ydash.getDfsNumber());
    } else {
      if (ydash.getDfsNumber() != w) {
        if (!nodePool.hasSome(function (e) { return e == ydash; })) {
          workList.append(ydash);
          nodePool.append(ydash);
        }
      }
    }
  });
};

HavlakLoopFinder.prototype.setLoopAttributes = async function (w, nodePool, loop) {
  // At this point, one can set attributes to the loop, such as:
  //
  // the bottom node:
  //    iter  = backPreds[w].begin();
  //    loop bottom is: nodes[iter].node);
  //
  // the number of backedges:
  //    backPreds[w].size()
  //
  // whether this loop is reducible:
  //    type[w] != BasicBlockClass.BB_IRREDUCIBLE
  //
  this.nodes[w].setLoop(loop);
  var that = this;

  await nodePool.asyncForEach(async function (node) {
    // Add nodes to loop descriptor.
    that.header[node.getDfsNumber()] = w;
    node.union(that.nodes[w]);

    // Nested loops are not added, but linked together.
    if (node.getLoop()) {
      await node.getLoop().set_parent(loop);
    } else {
      await loop.add_node(node.getBb());
    }
  });
};

HavlakLoopFinder.prototype.stepD = function (w, nodePool) {
  var that = this;
  this.backPreds.at(w).forEach(function (v) {
    if (v != w) {
      nodePool.append(that.nodes[v].findSet());
    } else {
      that.type[w] = "BB_SELF";
    }
  });
};

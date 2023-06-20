# written by people at Computing Software Group, The University of Tokyo.

require 'jscall'

def setup
    $parser = Jscall.exec 'require("@babel/parser")'
    $generator = Jscall.exec 'require("@babel/generator")'
    $traverser = Jscall.exec 'require("@babel/traverse")'

    Jscall.exec <<~JS
        let node_class = null
        function set_node_class(ast) {
            node_class = ast.constructor
        }
        function get_children(node) {
            const children = []
            for (const prop in node) {
                const c = node[prop]
                if (c instanceof node_class)
                    children.push(c)
                else if (c instanceof Array)
                    for (const e of c)
                        if (e instanceof node_class)
                            children.push(e)
            }
            return children
        }
        function set_defuse(node, value) {
            node.defuse = value
        }
    JS
    ast = $parser.parse 'const a = 1'
    Jscall.set_node_class(ast)
end

class DefUse
    attr_accessor :declarator
    attr_reader :users

    def initialize(declarator)
        @declarator = declarator
        @declarator_identifier = declarator&.id
        @users = []
    end
    def addUse(user)
        @users << user unless @declarator_identifier == user
    end
end

class NameScope
    def initialize(parent = nil)
        @parent = parent
        @defuse_map = {}
    end

    def add_def(name, ast_node)
        if @defuse_map.include? name
            defuse = @defuse_map[name]
            defuse.declarator = ast_node
            defuse
        else
            defuse = DefUse.new(ast_node)
            @defuse_map[name] = defuse
            defuse
        end
    end

    def add_use(name, ast_node)
        if @defuse_map.include? name
            defuse = @defuse_map[name]
            defuse.addUse(ast_node)
            defuse
        else
            @parent&.add_use(name, ast_node)
        end
    end

    def size
        @defuse_map.size
    end

    def dump
        @defuse_map.map do |k, v|
            [k, v.users.size]
        end
    end
end

# Finds def-use relations by an inaccurate algorithm.
#
def traverse_tree(ast, name_scope)
    type = ast.type
    if type == 'VariableDeclarator'
        id = ast.id
        if id.type == 'Identifier'
            defuse = name_scope.add_def(id.name, ast)
            ast.defuse = defuse
        end
    elsif type == 'Identifier'
        defuse = name_scope.add_use(ast.name, ast) ||
                 name_scope.add_def(ast.name, nil)
        ast.defuse = defuse
    elsif type == 'BlockStatement'
        name_scope = NameScope.new(name_scope)
    end
    children = Jscall.get_children(ast)
    children.each {|t| traverse_tree(t, name_scope) }
end

#ast = $parser.parse <<CODE
#  const a = 1; let b = a + 2; b = a;
#  function foo(x) {
#    return x + a
#  }
#CODE

#Jscall.console.log(ast.program.body)

def make_defuse(file_name)
    src = File.read(file_name)
    ast = $parser.parse(src)
    scope = NameScope.new
    traverse_tree(ast, scope)
    # p scope.dump
    scope.size
end

def generate
    handler = Jscall.exec <<CODE
   ({
     enter(path) {
       console.log(path.node.type)
       // Ruby.exec('p "call"')
     }
   })
CODE
    $traverser.default(ast, handler)
    p $generator.default(ast).code
end

require_relative '../inspect'

def run_benchmark
    if ARGV.length > 0 && ARGV[0] == 'true'
        require '../install_refgraph'
    end

    if ARGV.length > 1 && ARGV[1] == 'true'
        Refgraph.force_immediate_gc
    end

    file_name = './index.js'
    setup
    GC::Profiler.enable
    10.times do
        t00 = Refgraph.clock
        make_defuse(file_name)
        Refgraph.logging(t00)
    end
end

run_benchmark

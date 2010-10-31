module Neo4j
  module Mapping

    # Enables creating and traversal of nodes.
    # Includes the Enumerable Mixin.
    #
    class HasN
      include Enumerable
      include ToJava

      def initialize(node, dsl) # :nodoc:
        @node = node
        @direction = dsl.direction
        @dsl = @direction == :outgoing ? dsl : dsl.incoming_dsl
      end

      def to_s
        "HasN [#@direction, #{@node.neo_id} #{@dsl.namespace_type}]"
      end

      def size
        [*self].size
      end

      alias_method :length, :size

      def [](index)
        each_with_index {|node,i| break node if index == i}
      end

      # Pretend we are an array - this is neccessarly for Rails actionpack/actionview/formhelper to work with this
      def is_a?(type)
        # ActionView requires this for nested attributes to work
        return true if Array == type
        super
      end

      # Required by the Enumerable mixin.
      def each(&block)
        @dsl.each_node(@node, @direction, &block)
      end


      # Returns true if there are no node in this type of relationship
      def empty?
        first == nil
      end


      # Creates a relationship instance between this and the other node.
      # Returns the relationship object
      def new(other)
        @dsl.create_relationship_to(@node, other)
      end


      # Creates a relationship between this and the other node.
      #
      # ==== Example
      # 
      #   n1 = Node.new # Node has declared having a friend type of relationship
      #   n2 = Node.new
      #   n3 = Node.new
      #
      #   n1 << n2 << n3
      #
      # ==== Returns
      # self
      #
      def <<(other)
        @dsl.create_relationship_to(@node, other)
        self
      end
    end

  end
end

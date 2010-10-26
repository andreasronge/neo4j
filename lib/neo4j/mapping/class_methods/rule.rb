module Neo4j::Mapping
  module ClassMethods
    class Rules
      class << self
        def add(clazz, field, props, &block)
          clazz = clazz.to_s
          @rules ||= {}
          # was there no ruls for this class AND is neo4j running ?
          if !@rules.include?(clazz) && Neo4j.running?
            # maybe Neo4j was started first and the rules was added later. Create rule nodes now
            create_rule_node_for(clazz)
          end
          @rules[clazz] ||= {}
          filter = block.nil? ? Proc.new { |*| true } : block
          @rules[clazz][field] = filter
          @triggers ||= {}
          @triggers[clazz] ||= {}
          trigger = props[:trigger].nil? ? [] : props[:trigger]
          @triggers[clazz][field] = trigger.respond_to?(:each) ? trigger : [trigger]
        end
	
	def inherit(parent_class, subclass)
	  # copy all the rules
	  @rules[parent_class.to_s].each_pair do |field, filter|
	    subclass.rule field, &filter
	  end if @rules[parent_class.to_s]
	end

        def trigger_other_rules(node)
	  clazz = node[:_classname]
	  @rules[clazz].keys.each do |field|
	    rel_types = @triggers[clazz][field]
	    rel_types.each do |rel_type|
	      node.incoming(rel_type).each { |n| n.trigger_rules }
	    end
	  end
        end

        def fields_for(clazz)
          clazz = clazz.to_s
          return [] if @rules.nil? || @rules[clazz].nil?
          @rules[clazz].keys
        end

        def delete(clazz)
          clazz = clazz.to_s
          # delete the rule node if found
          if Neo4j.ref_node.rel?(clazz)
            Neo4j.ref_node.outgoing(clazz).each { |n| n.del }
          end
          @rules.delete(clazz) if @rules
        end

        def on_neo4j_started(*)
          @rules.each_key { |clazz| create_rule_node_for(clazz) } if @rules
        end

        def create_rule_node_for(clazz)
          if !Neo4j.ref_node.rel?(clazz)
            Neo4j::Transaction.run do
              node = Neo4j::Node.new
              Neo4j.ref_node.outgoing(clazz) << node
              node
            end
          end
        end

        def trigger?(node)
          @rules && node.property?(:_classname) && @rules.include?(node[:_classname])
        end

        def rule_for(clazz)
	  if Neo4j.ref_node.rel?(clazz)
	    Neo4j.ref_node._rel(:outgoing, clazz)._end_node
	  else
	    # this should be called if the rule node gets deleted
	    create_rule_node_for(clazz)
	  end
        end


        def on_relationship_created(rel, *)
	  trigger_start_node = trigger?(rel._start_node)
          trigger_end_node   = trigger?(rel._end_node)
          # end or start node must be triggered by this event
          return unless trigger_start_node || trigger_end_node
          on_property_changed(trigger_start_node ? rel._start_node : rel._end_node)
        end


        def on_property_changed(node, *)
	  trigger_rules(node) if trigger?(node)
        end

        def trigger_rules(node)
          trigger_rules_for_class(node, node[:_classname])
	  trigger_other_rules(node)
        end
	
	def trigger_rules_for_class(node, clazz)
	  return if @rules[clazz].nil?

          agg_node = rule_for(clazz)
          @rules[clazz].each_pair do |field, rule|
            if run_rule(rule, node)
              # is this node already included ?
	      unless connected?(field, agg_node, node)
                agg_node.outgoing(field) << node
              end
            else
              # remove old ?
	      break_connection(field, agg_node, node)
            end
          end
	  
	  # recursively add relationships for all the parent classes with rules that also pass for this node
	  if clazz = eval("#{clazz}.superclass")
	    trigger_rules_for_class(node, clazz.to_s)
	  end
	end
	
	# work out if two nodes are connected by a particular relationship
	# uses the end_node to start with because it's more likely to have less relationships to go through
	# (just the number of superclasses it has really)
	def connected?(relationship, start_node, end_node)
	  end_node.incoming(relationship).each do |n|
	    return true if n == start_node
	  end
	  false
	end
	
	# sever a direct one-to-one relationship if it exists
	def break_connection(relationship, start_node, end_node)
	  end_node.rels(relationship).incoming.each do |r|
	    return r.del if r.start_node == start_node
	  end
	end

        def run_rule(rule, node)
          if rule.arity != 1
            node.wrapper.instance_eval(&rule)
          else
            rule.call(node)
          end
        end
      end
    end


    module Rule

      # Creates an rule node attached to the Neo4j.ref_node
      # Can be used to rule all instances of a specific Ruby class.
      #
      # Example of usage:
      #   class Person
      #     include Neo4j
      #     rule :all
      #     rule :young { self[:age] < 10 }
      #   end
      #
      #   p1 = Person.new :age => 5
      #   p2 = Person.new :age => 7
      #   p3 = Person.new :age => 12
      #   Neo4j::Transaction.finish
      #   Person.all    # =>  [p1,p2,p3]
      #   Person.young  # =>  [p1,p2]
      #   p1.young?    # => true
      #
      def rule(name, props = {}, &block)
	singelton = class << self;
          self;
        end
	
        # define class methods
        singelton.send(:define_method, name) do
          agg_node = Rules.rule_for(self)
          raise "no rule node for #{name}  on #{self}" if agg_node.nil?
          traversal = agg_node.outgoing(name) # TODO possible to cache this object
          Rules.fields_for(self).each do |filter_name|
            traversal.filter_method(filter_name) do |path|
              path.end_node.rel?(filter_name, :incoming)
            end
          end
          traversal
        end unless respond_to?(name)

        # define instance methods
        self.send(:define_method, "#{name}?") do
          instance_eval &block
	end

        Rules.add(self, name, props, &block)
      end
      
      def inherit_rules_from(clazz)
	Rules.inherit(clazz, self)
      end
      
      # This is typically used for RSpecs to clean up rule nodes created by the #rule method.
      # It also remove the given class method.
      def delete_rules
        singelton = class << self;
          self;
        end
        Rules.fields_for(self).each do |name|
          singelton.send(:remove_method, name)
        end
        Rules.delete(self)
      end

      def trigger_rules(node)
        Rules.trigger_rules(node)
      end

    end

    Neo4j.unstarted_db.event_handler.add(Rules)
  end
end

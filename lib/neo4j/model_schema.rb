require 'set'
module Neo4j
  # This is here to support the removed functionality of being able to
  # defined indexes and constraints on models
  # This code should be removed later
  module ModelSchema
    MODEL_INDEXES = {}
    MODEL_CONSTRAINTS = {}
    REQUIRED_INDEXES = {}

    class << self
      def add_defined_constraint(model, property_name)
        MODEL_CONSTRAINTS[model] ||= Set.new
        MODEL_CONSTRAINTS[model] << property_name.to_sym
      end

      def add_defined_index(model, property_name)
        MODEL_INDEXES[model] ||= Set.new
        MODEL_INDEXES[model] << property_name.to_sym
      end

      def add_required_index(model, property_name)
        REQUIRED_INDEXES[model] ||= Set.new
        REQUIRED_INDEXES[model] << property_name.to_sym
      end

      def defined_constraint?(model, property_name)
        MODEL_CONSTRAINTS[model] &&
          MODEL_CONSTRAINTS[model].include?(property_name.to_sym)
      end

      def model_constraints
        constraints = Neo4j::ActiveBase.current_session.constraints(nil, type: :uniqueness)

        schema_elements_list(MODEL_CONSTRAINTS, constraints)
      end

      def model_indexes
        indexes = Neo4j::ActiveBase.current_session.indexes(nil)

        schema_elements_list(MODEL_INDEXES, indexes) +
          schema_elements_list(REQUIRED_INDEXES, indexes).reject(&:last)
        # reject required indexes which are already in the DB
      end

      # should be private
      def schema_elements_list(by_model, db_results)
        by_model.flat_map do |model, property_names|
          label = model.mapped_label_name.to_s
          property_names.map do |property_name|
            exists = db_results[label] && db_results[label].include?([property_name])
            [model, label, property_name, exists]
          end
        end
      end

      def validate_model_schema!
        messages = {index: [], constraint: []}
        [[:constraint, model_constraints],
         [:index, model_indexes]].each do |type, schema_elements|
          schema_elements.map do |model, label, property_name, exists|
            if exists
              log_warning!(type, model, property_name)
            else
              messages[type] << force_add_message(type, label, property_name)
            end
          end
        end

        return if messages.values.all?(&:empty?)

        fail <<MSG
          Some schema elements were defined by the model (which is no longer support), but they do not exist in the database.  Run the following to create them:

#{messages[:constraint].join("\n")}
#{messages[:index].join("\n")}
MSG
      end

      def force_add_message(index_or_constraint, model_name, property_name)
        "rails generate migration ForceAdd#{index_or_constraint.to_s.capitalize}#{model_name.gsub(/[^a-z0-9]/i, '')}#{property_name.to_s.camelize} force_add_#{index_or_constraint} #{model_name} #{property_name}\n"
      end

      def log_warning!(index_or_constraint, model, property_name)
        Neo4j::ActiveBase.logger.warn "WARNING: The #{index_or_constraint} option is no longer supported (Defined on #{model.name} for #{property_name})"
      end
    end
  end
end
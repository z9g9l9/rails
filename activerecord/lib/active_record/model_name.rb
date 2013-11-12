module ActiveRecord
  class ModelName < String
    alias_method :cache_key, :collection

    def singular
      @singular ||= ActiveSupport::Inflector.underscore(self).tr('/', '_').freeze
    end

    def plural
      @plural ||= ActiveSupport::Inflector.pluralize(singular).freeze
    end

    def element
      @element ||= ActiveSupport::Inflector.underscore(ActiveSupport::Inflector.demodulize(self)).freeze
    end

    def collection
      @collection ||= ActiveSupport::Inflector.tableize(self).freeze
    end

    def partial_path
      @partial_path ||= "#{collection}/#{element}".freeze
    end
  end
end

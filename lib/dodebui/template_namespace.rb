module Dodebui
  # namespace for evaluationg templates
  class TemplateNamespace
    def initialize(hash)
      hash.each do |key, value|
        singleton_class.send(:define_method, key) { value }
      end
    end

    def priv_binding
      binding
    end
  end
end

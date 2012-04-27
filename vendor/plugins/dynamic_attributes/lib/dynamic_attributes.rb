module DynamicAttributes

  class UndefinedTableColumn < StandardError; end

  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    
    def attr_dynamic(attr_name, attr_type, options = {})
      include InstanceMethods
      
      has_many :dynamic_attributes, :as => :target, :dependent => :destroy
      
      # Clean up our arguments
      attr_name = attr_name.to_sym
      attr_type = attr_type.to_sym
      
      # Set up our class-level variables
      cattr_accessor :dynamic_attributes_options, :dynamic_attributes_fields
      
      # Store the options
      self.dynamic_attributes_options = options
      
      # Store the info about the new attribute
      self.dynamic_attributes_fields ||= {}
      self.dynamic_attributes_fields[attr_name] = { :type => attr_type }
      
      # Wire ourselves into important ActiveRecord methods
      class_eval do
        unless method_defined? :method_missing_without_dynamic_attributes
          # Carry out delayed actions before save
        	after_initialize :load_dynamic_attributes
          after_save :save_dynamic_attributes

          # Make attributes seem real
          alias_method_chain :method_missing, :dynamic_attributes
          
          private
              
          alias_method_chain :read_attribute, :dynamic_attributes
          alias_method_chain :write_attribute, :dynamic_attributes
        end
      end
      
    end
    
  end

  module InstanceMethods
    
    # Determines if the given attribute is a dynamic attribute.
    def is_dynamic_attribute?(attr)
      return dynamic_attributes_fields.include?(attr.to_sym) unless dynamic_attributes_fields.empty?
      return false if self.class.column_names.include?(attr.to_s)
      true
    end
    
    def has_attribute?(attr_name)
      return super || is_dynamic_attribute?(attr_name)
    end

    def attributes=(new_attributes, guard_protected_attributes = true)
      new_attributes.each do |k, v|
        if self.dynamic_attributes_fields.include?(k)
          write_dynamic_attribute(k, v)
          new_attributes.delete(k)
        end
      end
      
      super(new_attributes)
    end

    # def column_names
    #   super + dynamic_attributes_fields.keys
    # end

		def inspect
			model_inspect = super
			a = dynamic_attributes_fields.keys.map { |attr| "#{attr}: #{self[attr].inspect || 'nil'}" }
			dynamic_inspect = a.join(', ')
			"#{model_inspect[0..-2]} || #{dynamic_inspect}>"
		end

  private

		# after_initialize callback
    def load_dynamic_attributes
			@dynamic_attr_cache = {}
			self.dynamic_attributes.each do |d|
				@dynamic_attr_cache[d.key] = value_of_dynamic_attribute(d)
			end
		end

    def dynamic_attribute_hash
      result = {}
      self.dynamic_attributes_fields.each_key do |k| 
        result[k] = read_attribute_with_dynamic_attributes(k)
      end
      result
    end
  
    # We override this so we can include our defined dynamic attributes
    def attributes_from_column_definition
      unless dynamic_attributes_fields.empty?
        attributes = dynamic_attributes_fields.keys.inject({}) do |attributes, column|
          attributes[column.to_s] = nil
          attributes
        end
      end

      self.class.columns.inject(attributes || {}) do |attributes, column|
        attributes[column.name] = column.default unless column.name == self.class.primary_key
        attributes
      end
    end
  
    # Implements dynamic-attributes as if real getter/setter methods
    # were defined.
    def method_missing_with_dynamic_attributes(method_id, *args, &block)
      begin
        method_missing_without_dynamic_attributes method_id, *args, &block
      rescue NameError => e
        attr_name = method_id.to_s.sub(/\=$/, '')
        if is_dynamic_attribute?(attr_name)
          if method_id.to_s =~ /\=$/
            return write_attribute_with_dynamic_attributes(attr_name, args[0])
          else
            return read_attribute_with_dynamic_attributes(attr_name)
          end
        end
        raise e
      end
    end

    # Overrides ActiveRecord::Base#read_attribute
    def read_attribute_with_dynamic_attributes(attr_name)
      attr_name = attr_name.to_s
      if is_dynamic_attribute?(attr_name)
        return read_dynamic_attribute(attr_name)
      end
      
      read_attribute_without_dynamic_attributes(attr_name)
    end

    # Overrides ActiveRecord::Base#write_attribute
    def write_attribute_with_dynamic_attributes(attr_name, value)
      if is_dynamic_attribute?(attr_name)
        return write_dynamic_attribute(attr_name, value)
      end
      
      write_attribute_without_dynamic_attributes(attr_name, value)
    end
    
    def write_dynamic_attribute(attr_name, value)
      attr_name = attr_name.to_s
      return @dynamic_attr_cache[attr_name] = value
    end
    
    def read_dynamic_attribute(attr_name)
      if !@dynamic_attr_cache.blank? and @dynamic_attr_cache.has_key?(attr_name)
         return @dynamic_attr_cache[attr_name]
       else
         dynamic_attribute = self.dynamic_attributes.where(:key => attr_name.to_s).first
				 @dynamic_attr_cache[attr_name] = value_of_dynamic_attribute(dynamic_attribute)
				 return value_of_dynamic_attribute(dynamic_attribute)
       end
    end

		def value_of_dynamic_attribute(dynamic_attribute)
			if dynamic_attribute.blank?
        return nil
      else
        case self.dynamic_attributes_fields[dynamic_attribute.key.to_sym][:type].to_sym
        when :string
          return dynamic_attribute.value
        when :integer
          return dynamic_attribute.value.to_i
        when :datetime
          return DateTime.parse(dynamic_attribute.value)
        else
          return dynamic_attribute.value
        end
      end
		end

    # Called after validation on update so that dynamic attributes behave
    # like normal attributes in the fact that the database is not touched
    # until save is called.
    def save_dynamic_attributes
      return if @dynamic_attr_cache.blank?
			
      @dynamic_attr_cache.each do |attr_name, attr_value|
        dynamic_attribute = self.dynamic_attributes.where(:key => attr_name).first
        if dynamic_attribute.blank?
					unless attr_value.nil?
	          # Create a new attribute
	          dynamic_attribute = DynamicAttribute.create(:target => self, :key => attr_name.to_s, :value => attr_value.to_s)
	          self.dynamic_attributes << dynamic_attribute          
					end
        elsif attr_value.nil?
          # Destory the attribute if nil
          dynamic_attribute.destroy
        else
          # Update the attribute
          dynamic_attribute.update_attribute(:value, attr_value.to_s)
        end
      end
      
    end
    
  end

end

ActiveRecord::Base.send :include, DynamicAttributes
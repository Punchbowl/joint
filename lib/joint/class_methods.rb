module Joint
  module ClassMethods
    def set_joint_collection(name)
      self.joint_collection_name = name.to_s
    end

    def attachment(name, options = {})
      options.symbolize_keys!
      name = name.to_sym
      accessor_name = options[:accessor_name] || name.to_sym

      self.attachment_names = attachment_names.dup.add(name)

      unless options[:readonly]
        after_save     :save_attachments
        before_save    :nullify_nil_attachments_attributes
        after_save     :destroy_nil_attachments
        before_destroy :destroy_all_attachments
      end

      key :"#{name}_id",   ObjectId
      key :"#{name}_name", String
      key :"#{name}_size", Integer
      key :"#{name}_type", String

      validates_presence_of(name) if options[:required]

      self.class_eval <<-EOC
        def #{accessor_name}
          @#{accessor_name} ||= AttachmentProxy.new(self, :#{name})
        end

        def #{accessor_name}?
          !nil_attachments.has_key?(:#{name}) && send(:#{name}_id?)
        end
      EOC

      unless options[:readonly]
        self.class_eval <<-EOC
          def #{accessor_name}=(file)
            if file.nil?
              nil_attachments[:#{name}] = send("#{name}_id")
              assigned_attachments.delete(:#{name})
            else
              send("#{name}_id=", BSON::ObjectId.new) if send("#{name}_id").nil?
              send("#{name}_name=", Joint::FileHelpers.name(file))
              send("#{name}_size=", Joint::FileHelpers.size(file))
              send("#{name}_type=", Joint::FileHelpers.type(file))
              assigned_attachments[:#{name}] = file
              nil_attachments.delete(:#{name})
            end
          end
        EOC
      end
    end
  end
end

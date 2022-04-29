module Joint
  def grid
    @grid ||= database.fs(bucket_name: joint_collection_name)
  end

  private
    def assigned_attachments
      @assigned_attachments ||= {}
    end

    def nil_attachments
      @nil_attachments ||= {}
    end

    # IO must respond to read and rewind
    def save_attachments
      assigned_attachments.each_pair do |name, io|
        next unless io.respond_to?(:read)
        io.rewind if io.respond_to?(:rewind)
        delete_file(send(name).id)
        grid.upload_from_stream(
          send(name).name,
          io,
          {
            file_id: send(name).id,
            metadata: { content_type: send(name).type },
          }
        )
      end
      assigned_attachments.clear
    end
    
    def nullify_nil_attachments_attributes
      nil_attachments.each_key do |name|
        send(:"#{name}_id=", nil)
        send(:"#{name}_size=", nil)
        send(:"#{name}_type=", nil)
        send(:"#{name}_name=", nil)
      end
    end

    def destroy_nil_attachments
      nil_attachments.each_value do |id|
        delete_file(id)
      end

      nil_attachments.clear
    end

    def destroy_all_attachments
      self.class.attachment_names.map do |name|
        delete_file(send(name).id)
      end
    end

    def delete_file(file_id)
      file_id = BSON::ObjectId(file_id) if file_id.is_a?(String)
      begin
        grid.delete(file_id)
      rescue Mongo::Error::FileNotFound => e
        Rails.logger.warn(e.message)
      end
    end
end

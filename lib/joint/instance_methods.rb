module Joint
  def fs_bucket
    @fs_bucket ||= database.fs(bucket_name: joint_collection_name)
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
        fs_bucket.delete(send(name).id) rescue Mongo::Error::FileNotFound
        fs_bucket.open_upload_stream(send(name).name, {
          file_id: send(name).id,
          content_type: send(name).type
        }) { |stream| stream.write(io) }
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
        fs_bucket.delete(id)
      end

      nil_attachments.clear
    end

    def destroy_all_attachments
      self.class.attachment_names.map do |name|
        fs_bucket.delete(send(name).id) rescue Mongo::Error::FileNotFound
      end
    end
end

module Joint
  def grid
    @grid ||= database.fs(bucket_name: joint_collection_name)
  end

  # An AttachmentProxy holds a reference to the record it was built from and reads
  # `<name>_id` off it, and the pending-upload bookkeeping is shared by reference after
  # a clone. Neither may survive a copy: left in place, the copy's `save_attachments`
  # deletes and rewrites the *source's* GridFS files while the copy's own ids point at
  # nothing.
  def initialize_copy(other)
    super

    instance_variables.each do |ivar|
      remove_instance_variable(ivar) if instance_variable_get(ivar).is_a?(AttachmentProxy)
    end

    @assigned_attachments = nil
    @nil_attachments      = nil
    @grid                 = nil
  end

  # Detach this record from the GridFS files it inherited from the record it was copied
  # from, so that saving uploads its own. Detaches every attachment unless given names.
  #
  # The attachment writers mint a new id only when the current one is nil, which is what
  # makes replacing a file in place work -- and what makes a copy silently overwrite its
  # source. This clears the ids so the next assignment gets fresh ones.
  #
  # Deliberately writes the plain `<name>_id/_name/_size/_type` keys rather than going
  # through the attachment writers: `send(:"#{name}=", nil)` would register the old ids
  # in `nil_attachments`, and the after_save `destroy_nil_attachments` would then delete
  # the source's files outright.
  def detach_attachments!(*names)
    names = self.class.attachment_names.to_a if names.empty?

    names.map(&:to_sym).each do |name|
      send(:"#{name}_id=",   nil)
      send(:"#{name}_name=", nil)
      send(:"#{name}_size=", nil)
      send(:"#{name}_type=", nil)
    end
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
            content_type: send(name).type,
            file_id: send(name).id,
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
        # Joint does not depend on Rails; outside of it (including this gem's own test
        # suite) there is no Rails.logger to warn through.
        Rails.logger.warn(e.message) if defined?(Rails) && Rails.respond_to?(:logger)
      end
    end
end

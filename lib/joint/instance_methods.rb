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

    reset_attachment_proxies!
    @assigned_attachments = nil
    @nil_attachments      = nil
    @grid                 = nil
  end

  # Give this record its own copies of another record's attachments. The bytes are
  # re-uploaded under fresh GridFS ids on save, with the original file names and content
  # types, exactly as if the same files had been uploaded to a new record. Copies every
  # attachment unless given names.
  #
  # This is what you want after `clone`: a clone inherits the source's attachment ids,
  # and the writers only mint a new id when the current one is nil, so a clone that is
  # saved with a new file writes over the source's blob instead of its own.
  #
  #   copy = doc.clone
  #   copy.copy_attachments_from!(doc)
  #   copy.save!
  def copy_attachments_from!(source, *names)
    names = self.class.attachment_names.to_a if names.empty?

    names.map(&:to_sym).each do |name|
      # Read before detaching, so that copying a record onto itself still works.
      io = source.send(:"#{name}?") ? attachment_upload_for(source, name) : nil

      detach_attachments!(name)
      send(:"#{name}=", io) if io
    end
  end

  # Detach this record from the GridFS files it inherited from the record it was copied
  # from, so that saving cannot touch them. Detaches every attachment unless given names.
  #
  # Deliberately writes the plain `<name>_id/_name/_size/_type` keys rather than going
  # through the attachment writers: `send(:"#{name}=", nil)` would register the old ids
  # in `nil_attachments`, and the after_save `destroy_nil_attachments` would then delete
  # the source's files outright. Any `nil_attachments` entry already queued is dropped
  # for the same reason -- detaching means this record no longer owns those files.
  #
  # Order-independent with respect to assignment: an attachment that already has a file
  # queued keeps it and is given a fresh id to upload to, rather than being reset to nil
  # and uploading an orphan the record never references.
  def detach_attachments!(*names)
    names = self.class.attachment_names.to_a if names.empty?
    names = names.map(&:to_sym)

    names.each do |name|
      nil_attachments.delete(name)

      if assigned_attachments[name]
        send(:"#{name}_id=", BSON::ObjectId.new)
      else
        send(:"#{name}_id=",   nil)
        send(:"#{name}_name=", nil)
        send(:"#{name}_size=", nil)
        send(:"#{name}_type=", nil)
      end
    end

    reset_attachment_proxies!(names)
  end

  private
    # A proxy reads its attachment's keys off the record it was built from and memoizes
    # its GridFS stream, so it must not outlive a copy or an id change. Matches on the
    # proxy itself rather than on `attachment_names`, because the memoizing ivar is named
    # after the attachment's accessor_name, which Joint does not record.
    def reset_attachment_proxies!(names=nil)
      instance_variables.each do |ivar|
        proxy = instance_variable_get(ivar)
        next unless proxy.is_a?(AttachmentProxy)
        next if names && !names.include?(proxy.attachment_name)

        remove_instance_variable(ivar)
      end
    end

    # Wraps another record's attachment as an upload, preserving the stored file name and
    # content type. Joint::IO is the one IO that FileHelpers reads a type off directly,
    # so the copy does not get re-sniffed or named after a temp file.
    def attachment_upload_for(source, name)
      Joint::IO.new(
        name:    source.send(:"#{name}_name") || name.to_s,
        type:    source.send(:"#{name}_type"),
        content: source.send(name).read
      )
    end

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
        # suite) there is no Rails.logger to warn through, and even under Rails the
        # logger can be unset during early boot.
        Rails.logger&.warn(e.message) if defined?(Rails) && Rails.respond_to?(:logger)
      end
    end
end

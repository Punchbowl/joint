require 'bundler/setup'
Bundler.setup(:default, 'test', 'development')

require 'logger'
require 'byebug'
require 'tempfile'
require 'mongo_mapper'

require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/pride'
require 'mocha/mini_test'

require File.expand_path(File.dirname(__FILE__) + '/../lib/joint')

log_dir = File.expand_path('../../log', __FILE__)
FileUtils.mkdir_p(log_dir)
logger = Logger.new(File.join(log_dir, 'test.log'))

MongoMapper.connection = Mongo::Client.new(['127.0.0.1:27017'], :database => 'joint_test', :logger => logger)
MongoMapper.database = "joint_test"
MongoMapper.database.collections.each { |c| c.indexes.drop_all }

class Minitest::Test
  def setup
    MongoMapper.database.collections.each { |coll| coll.drop unless coll.name =~ /^system/ }
  end

  def assert_difference(expression, difference = 1, message = nil, &block)
    b      = block.send(:binding)
    exps   = Array.wrap(expression)
    before = exps.map { |e| eval(e, b) }
    yield
    exps.each_with_index do |e, i|
      error = "#{e.inspect} didn't change by #{difference}"
      error = "#{message}.\n#{error}" if message
      after = eval(e, b)
      assert_equal(before[i] + difference, after, error)
    end
  end

  def assert_no_difference(expression, message = nil, &block)
    assert_difference(expression, 0, message, &block)
  end

  def assert_grid_difference(difference=1, collection_name='fs', &block)
    assert_difference("MongoMapper.database['#{collection_name}.files'].find().count", difference, &block)
  end

  def assert_no_grid_difference(collection_name = 'fs', &block)
    assert_grid_difference(0, collection_name, &block)
  end
end

class Basic
  include MongoMapper::Document
  has_many :embedded_assets
end

class Asset
  include MongoMapper::Document
  plugin Joint

  key :title, String
  attachment :image
  attachment :file
  has_many :embedded_assets
end

class CustomCollectionAsset < Asset
  set_joint_collection :custom
end

class CustomCollectionAssetSubclass < CustomCollectionAsset
  attachment :video
end

class EmbeddedAsset
  include MongoMapper::EmbeddedDocument
  plugin Joint

  key :title, String
  attachment :image
  attachment :file
end

class BaseModel
  include MongoMapper::Document
  plugin Joint
  attachment :file
end

class Image < BaseModel; attachment :image end
class Video < BaseModel; attachment :video end

module JointTestHelpers
  def all_files
    [@file, @image, @image2, @test1, @test2]
  end

  def rewind_files
    all_files.each { |file| file.rewind }
  end

  def open_file(name)
    f = File.open(File.join(File.dirname(__FILE__), 'fixtures', name), 'r')
    f.binmode
    f
  end

  def fs_bucket(collection_name = 'fs')
    @fs_buckets ||= {}
    @fs_buckets[collection_name] ||= MongoMapper.database.fs(bucket_name: collection_name)
  end

  def key_names
    [:id, :name, :type, :size]
  end
end

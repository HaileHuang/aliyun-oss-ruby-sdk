# -*- encoding: utf-8 -*-

require 'spec_helper'
require 'yaml'
require 'nokogiri'

module Aliyun
  module OSS

    describe "Object" do

      before :all do
        @endpoint = 'oss.aliyuncs.com'

        cred_file = "~/.oss.yml"
        cred = YAML.load(File.read(File.expand_path(cred_file)))
        Aliyun::OSS::Logging.set_log_level(Logger::DEBUG)

        @oss = Client.new(@endpoint, cred['id'], cred['key'])
        @bucket = 'rubysdk-bucket'
      end

      def get_request_path(object = nil)
        p = "#{@bucket}.#{@endpoint}/"
        p += object if object
        p
      end

      def get_resource_path(object)
        "/#{@bucket}/#{object}"
      end

      def mock_copy_object(last_modified, etag)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.CopyObjectResult {
            xml.LastModified last_modified.to_s
            xml.ETag etag
          }
        end

        builder.to_xml
      end

      def mock_acl(acl)
        Nokogiri::XML::Builder.new do |xml|
          xml.AccessControlPolicy {
            xml.Owner {
              xml.ID 'owner_id'
              xml.DisplayName 'owner_name'
            }

            xml.AccessControlList {
              xml.Grant acl
            }
          }
        end.to_xml
      end

      def mock_delete(objects, opts = {})
        Nokogiri::XML::Builder.new do |xml|
          xml.Delete {
            xml.Quiet opts[:quiet]? true : false
            objects.each do |o|
              xml.Object {
                xml.Key o
              }
            end
          }
        end.to_xml
      end

      def mock_delete_result(deleted)
        Nokogiri::XML::Builder.new do |xml|
          xml.DeleteResult {
            deleted.each do |o|
              xml.Deleted {
                xml.Key o
              }
            end
          }
        end.to_xml
      end

      def mock_error(code, message)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.Error {
            xml.Code code
            xml.Message message
            xml.RequestId '0000'
          }
        end

        builder.to_xml
      end

      context "Put object" do

        it "should PUT to create object" do
          object_name = 'ruby'
          url = get_request_path(object_name)
          stub_request(:put, url)

          content = "hello world"
          @oss.put_object(@bucket, object_name) do |c|
            c << content
          end

          expect(WebMock).to have_requested(:put, url)
            .with(:body => content, :query => {})
        end

        it "should PUT to create object from file" do
          object_name = 'ruby'
          url = get_request_path(object_name)
          stub_request(:put, url)

          file = '/tmp/x'
          content = "hello world"
          File.open(file, 'w') {|f| f.write(content)}
          @oss.put_object_from_file(@bucket, object_name, file)

          expect(WebMock).to have_requested(:put, url)
            .with(:body => content, :query => {})
        end

        it "should raise Exception on error" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          code = 'NoSuchBucket'
          message = 'The bucket does not exist.'
          stub_request(:put, url).to_return(
            :status => 404, :body => mock_error(code, message))

          content = "hello world"
          expect {
            @oss.put_object(@bucket, object_name) do |c|
              c << content
            end
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:put, url)
            .with(:body => content, :query => {})
        end
      end # put object

      context "Append object" do

        it "should POST to append object" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          query = {'append' => '', 'position' => 11}
          stub_request(:post, url).with(:query => query)

          content = "hello world"
          @oss.append_object(@bucket, object_name, 11) do |c|
            c << content
          end

          expect(WebMock).to have_requested(:post, url)
            .with(:body => content, :query => query)
        end

        it "should POST to append object from file" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          query = {'append' => '', 'position' => 11}
          stub_request(:post, url).with(:query => query)

          file = '/tmp/x'
          content = "hello world"
          File.open(file, 'w') {|f| f.write(content)}
          @oss.append_object_from_file(@bucket, object_name, 11, file)

          expect(WebMock).to have_requested(:post, url)
            .with(:body => content, :query => query)
        end

        it "should raise Exception on error" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          query = {'append' => '', 'position' => 11}
          code = 'ObjectNotAppendable'
          message = 'Normal object cannot be appended.'
          stub_request(:post, url).with(:query => query).
            to_return(:status => 409, :body => mock_error(code, message))

          content = "hello world"
          expect {
            @oss.append_object(@bucket, object_name, 11) do |c|
              c << content
            end
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:post, url)
            .with(:body => content, :query => query)
        end
      end # put object

      context "Copy object" do

        it "should PUT to copy object" do
          src_object = 'ruby'
          dst_object = 'rails'
          url = get_request_path(dst_object)

          stub_request(:put, url)

          @oss.copy_object(@bucket, src_object, dst_object)

          expect(WebMock).to have_requested(:put, url)
            .with(:body => nil, :headers => {
                    'x-oss-copy-source' => get_resource_path(src_object)})
        end

        it "should parse copy object result" do
          src_object = 'ruby'
          dst_object = 'rails'
          url = get_request_path(dst_object)

          last_modified = Time.parse(Time.now.rfc822)
          etag = '0000'
          stub_request(:put, url).to_return(
            :body => mock_copy_object(last_modified, etag))

          result = @oss.copy_object(@bucket, src_object, dst_object)

          expect(WebMock).to have_requested(:put, url)
            .with(:body => nil, :headers => {
                    'x-oss-copy-source' => get_resource_path(src_object)})

          expect(result[:last_modified]).to eq(last_modified)
          expect(result[:etag]).to eq(etag)
        end

        it "should raise Exception on error" do
          src_object = 'ruby'
          dst_object = 'rails'
          url = get_request_path(dst_object)

          code = 'EntityTooLarge'
          message = 'The object to copy is too large.'
          stub_request(:put, url).to_return(
            :status => 400, :body => mock_error(code, message))

          expect {
            @oss.copy_object(@bucket, src_object, dst_object)
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:put, url)
            .with(:body => nil, :headers => {
                  'x-oss-copy-source' => get_resource_path(src_object)})
        end
      end # copy object

      context "Get object" do

        it "should GET to get object" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          return_content = "hello world"
          stub_request(:get, url).to_return(:body => return_content)

          content = ""
          @oss.get_object(@bucket, object_name) {|c| content << c}

          expect(WebMock).to have_requested(:get, url)
            .with(:body => nil, :query => {})

          expect(content).to eq(return_content)
        end

        it "should get object to file" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          return_content = "hello world"
          stub_request(:get, url).to_return(:body => return_content)

          file = '/tmp/x'
          @oss.get_object_to_file(@bucket, object_name, file)

          expect(WebMock).to have_requested(:get, url)
            .with(:body => nil, :query => {})

          expect(File.read(file)).to eq(return_content)
        end

        it "should raise Exception on error" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          code = 'NoSuchKey'
          message = 'The object does not exist'
          stub_request(:get, url).to_return(
            :status => 404, :body => mock_error(code, message))

          expect {
            @oss.get_object(@bucket, object_name) {|c| true}
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:get, url)
            .with(:body => nil, :query => {})
        end

      end # Get object

      context "Delete object" do

        it "should DELETE to delete object" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          stub_request(:delete, url)

          @oss.delete_object(@bucket, object_name)

          expect(WebMock).to have_requested(:delete, url)
            .with(:body => nil, :query => {})
        end

        it "should raise Exception on error" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          code = 'NoSuchBucket'
          message = 'The bucket does not exist.'
          stub_request(:delete, url).to_return(
            :status => 404, :body => mock_error(code, message))

          expect {
            @oss.delete_object(@bucket, object_name)
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:delete, url)
            .with(:body => nil, :query => {})
        end

        it "should batch delete objects" do
          url = get_request_path
          query = {'delete' => ''}

          object_names = (1..5).map do |i|
            "object-#{i}"
          end

          stub_request(:post, url)
            .with(:query => query)
            .to_return(:body => mock_delete_result(object_names))

          deleted = @oss.batch_delete_objects(@bucket, object_names)

          expect(WebMock).to have_requested(:post, url)
            .with(:query => query, :body => mock_delete(object_names))
          expect(deleted).to match_array(object_names)
        end
      end # delete object

      context "acl" do
        it "should update acl" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          query = {'acl' => ''}
          stub_request(:put, url).with(:query => query)

          @oss.update_object_acl(@bucket, object_name, Object::ACL::PUBLIC_READ)

          expect(WebMock).to have_requested(:put, url)
            .with(:query => query,
                  :headers => {'x-oss-acl' => Object::ACL::PUBLIC_READ},
                  :body => nil)
        end

        it "should get acl" do
          object_name = 'ruby'
          url = get_request_path(object_name)

          query = {'acl' => ''}
          return_acl = Object::ACL::PUBLIC_READ

          stub_request(:get, url)
            .with(:query => query)
            .to_return(:body => mock_acl(return_acl))

          acl = @oss.get_object_acl(@bucket, object_name)

          expect(WebMock).to have_requested(:get, url)
            .with(:body => nil, :query => query)
          expect(acl).to eq(return_acl)
        end
      end # acl

    end # Object

  end # OSS
end # Aliyun
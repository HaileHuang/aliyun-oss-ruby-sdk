# -*- encoding: utf-8 -*-

require 'spec_helper'
require 'yaml'
require 'nokogiri'

module Aliyun
  module OSS

    describe Multipart do

      before :all do
        @endpoint = 'oss.aliyuncs.com'
        Config.set_endpoint(@endpoint)
        Config.set_credentials('xxx', 'yyy')

        @bucket = 'rubysdk-bucket'
        @object = 'rubysdk-object'
      end

      def request_path
        "#{@bucket}.#{@endpoint}/#{@object}"
      end

      def mock_txn_id(txn_id)
        Nokogiri::XML::Builder.new do |xml|
          xml.InitiateMultipartUploadResult {
            xml.Bucket @bucket
            xml.Key @object
            xml.UploadId txn_id
          }
        end.to_xml
      end

      def mock_multiparts(multiparts, more = {})
        Nokogiri::XML::Builder.new do |xml|
          xml.ListMultipartUploadsResult {
            {
              :prefix => 'Prefix',
              :delimiter => 'Delimiter',
              :limit => 'MaxUploads',
              :id_marker => 'UploadIdMarker',
              :next_id_marker => 'NextUploadIdMarker',
              :key_marker => 'KeyMarker',
              :next_key_marker => 'NextKeyMarker',
              :truncated => 'IsTruncated',
              :encoding => 'EncodingType'
            }.map do |k, v|
              xml.send(v, more[k]) if more[k]
            end

            multiparts.each do |m|
              xml.Upload {
                xml.Key m.object
                xml.UploadId m.id
                xml.Initiated m.creation_time.rfc822
              }
            end
          }
        end.to_xml
      end

      def mock_parts(parts, more = {})
        Nokogiri::XML::Builder.new do |xml|
          xml.ListPartsResult {
            {
              :marker => 'PartNumberMarker',
              :next_marker => 'NextPartNumberMarker',
              :limit => 'MaxParts',
              :truncated => 'IsTruncated',
              :encoding => 'EncodingType'
            }.map do |k, v|
              xml.send(v, more[k]) if more[k]
            end

            parts.each do |p|
              xml.Part {
                xml.PartNumber p.number
                xml.LastModified p.last_modified.rfc822
                xml.ETag p.etag
                xml.Size p.size
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

      context "Initiate multipart upload" do

        it "should POST to create transaction" do
          query = {'uploads' => ''}
          stub_request(:post, request_path).with(:query => query)

          Protocol.begin_multipart(@bucket, @object,
                                   :metas => {
                                     'year' => '2015',
                                     'people' => 'mary'
                                   })

          expect(WebMock).to have_requested(:post, request_path)
                         .with(:body => nil, :query => query,
                               :headers => {
                                 'x-oss-meta-year' => '2015',
                                 'x-oss-meta-people' => 'mary'
                               })
        end

        it "should return transaction id" do
          query = {'uploads' => ''}
          return_txn_id = 'zyx'
          stub_request(:post, request_path).
            with(:query => query).
            to_return(:body => mock_txn_id(return_txn_id))

          txn_id = Protocol.begin_multipart(@bucket, @object)

          expect(WebMock).to have_requested(:post, request_path)
            .with(:body => nil, :query => query)
          expect(txn_id).to eq(return_txn_id)
        end

        it "should raise Exception on error" do
          query = {'uploads' => ''}

          code = 'InvalidArgument'
          message = 'Invalid argument.'
          stub_request(:post, request_path)
            .with(:query => query)
            .to_return(:status => 400, :body => mock_error(code, message))

          expect {
            Protocol.begin_multipart(@bucket, @object)
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:post, request_path)
            .with(:body => nil, :query => query)
        end
      end # initiate multipart

      context "Upload part" do

        it "should PUT to upload a part" do
          txn_id = 'xxxyyyzzz'
          part_no = 1
          query = {'partNumber' => part_no, 'uploadId' => txn_id}

          stub_request(:put, request_path).with(:query => query)

          Protocol.upload_part(@bucket, @object, txn_id, part_no) {}

          expect(WebMock).to have_requested(:put, request_path)
            .with(:body => nil, :query => query)
        end

        it "should return part etag" do
          part_no = 1
          txn_id = 'xxxyyyzzz'
          query = {'partNumber' => part_no, 'uploadId' => txn_id}

          return_etag = 'etag_1'
          stub_request(:put, request_path)
            .with(:query => query)
            .to_return(:headers => {'ETag' => return_etag})

          body = 'hello world'
          p = Protocol.upload_part(@bucket, @object, txn_id, part_no) do |content|
            content << body
          end

          expect(WebMock).to have_requested(:put, request_path)
            .with(:body => body, :query => query)
          expect(p.number).to eq(part_no)
          expect(p.etag).to eq(return_etag)
        end

        it "should raise Exception on error" do
          txn_id = 'xxxyyyzzz'
          part_no = 1
          query = {'partNumber' => part_no, 'uploadId' => txn_id}

          code = 'InvalidArgument'
          message = 'Invalid argument.'

          stub_request(:put, request_path)
            .with(:query => query)
            .to_return(:status => 400, :body => mock_error(code, message))

          expect {
            Protocol.upload_part(@bucket, @object, txn_id, part_no) {}
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:put, request_path)
            .with(:body => nil, :query => query)
        end

      end # upload part

      context "Upload part by copy object" do

        it "should PUT to upload a part by copy object" do
          txn_id = 'xxxyyyzzz'
          part_no = 1
          copy_source = "/#{@bucket}/src_obj"

          query = {'partNumber' => part_no, 'uploadId' => txn_id}
          headers = {'x-oss-copy-source' => copy_source}

          stub_request(:put, request_path)
            .with(:query => query, :headers => headers)

          Protocol.upload_part_from_object(@bucket, @object, txn_id, part_no, 'src_obj')

          expect(WebMock).to have_requested(:put, request_path)
            .with(:body => nil, :query => query, :headers => headers)
        end

        it "should return part etag" do
          txn_id = 'xxxyyyzzz'
          part_no = 1
          copy_source = "/#{@bucket}/src_obj"

          query = {'partNumber' => part_no, 'uploadId' => txn_id}
          headers = {'x-oss-copy-source' => copy_source}
          return_etag = 'etag_1'

          stub_request(:put, request_path)
            .with(:query => query, :headers => headers)
            .to_return(:headers => {'ETag' => return_etag})

          p = Protocol.upload_part_from_object(@bucket, @object, txn_id, part_no, 'src_obj')

          expect(WebMock).to have_requested(:put, request_path)
            .with(:body => nil, :query => query, :headers => headers)
          expect(p.number).to eq(part_no)
          expect(p.etag).to eq(return_etag)
        end

        it "should set range and conditions when copy" do
          txn_id = 'xxxyyyzzz'
          part_no = 1
          copy_source = "/#{@bucket}/src_obj"

          query = {'partNumber' => part_no, 'uploadId' => txn_id}
          headers = {
            'Range' => 'bytes=1-4',
            'x-oss-copy-source' => copy_source,
            'x-oss-copy-source-if-modified-since' => 'ms',
            'x-oss-copy-source-if-unmodified-since' => 'ums',
            'x-oss-copy-source-if-match' => 'me',
            'x-oss-copy-source-if-none-match' => 'ume'
          }
          return_etag = 'etag_1'

          stub_request(:put, request_path)
            .with(:query => query, :headers => headers)
            .to_return(:headers => {'ETag' => return_etag})

          p = Protocol.upload_part_from_object(
            @bucket, @object, txn_id, part_no, 'src_obj',
            {:range => [1, 5],
             :condition => {
               :if_modified_since => 'ms',
               :if_unmodified_since => 'ums',
               :if_match_etag => 'me',
               :if_unmatch_etag => 'ume'
             }})

          expect(WebMock).to have_requested(:put, request_path)
            .with(:body => nil, :query => query, :headers => headers)
          expect(p.number).to eq(part_no)
          expect(p.etag).to eq(return_etag)
        end

        it "should raise Exception on error" do
          txn_id = 'xxxyyyzzz'
          part_no = 1
          copy_source = "/#{@bucket}/src_obj"

          query = {'partNumber' => part_no, 'uploadId' => txn_id}
          headers = {'x-oss-copy-source' => copy_source}

          code = 'PreconditionFailed'
          message = 'Precondition check failed.'
          stub_request(:put, request_path)
            .with(:query => query, :headers => headers)
            .to_return(:status => 412, :body => mock_error(code, message))

          expect {
            Protocol.upload_part_from_object(@bucket, @object, txn_id, part_no, 'src_obj')
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:put, request_path)
            .with(:body => nil, :query => query, :headers => headers)
        end
      end # upload part by copy object

      context "Commit multipart" do

        it "should POST to complete multipart" do
          txn_id = 'xxxyyyzzz'

          query = {'uploadId' => txn_id}
          parts = (1..5).map do |i|
            Multipart::Part.new(:number => i, :etag => "etag_#{i}")
          end

          stub_request(:post, request_path).with(:query => query)

          Protocol.commit_multipart(@bucket, @object, txn_id, parts)

          parts_body = Nokogiri::XML::Builder.new do |xml|
            xml.CompleteMultipartUpload {
              parts.each do |p|
                xml.Part {
                  xml.PartNumber p.number
                  xml.ETag p.etag
                }
              end
            }
          end.to_xml

          expect(WebMock).to have_requested(:post, request_path)
            .with(:body => parts_body, :query => query)
        end

        it "should raise Exception on error" do
          txn_id = 'xxxyyyzzz'
          query = {'uploadId' => txn_id}

          code = 'InvalidDigest'
          message = 'Content md5 does not match.'

          stub_request(:post, request_path)
            .with(:query => query)
            .to_return(:status => 400, :body => mock_error(code, message))

          expect {
            Protocol.commit_multipart(@bucket, @object, txn_id, [])
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:post, request_path)
            .with(:query => query)
        end
      end # commit multipart

      context "Abort multipart" do

        it "should DELETE to abort multipart" do
          txn_id = 'xxxyyyzzz'

          query = {'uploadId' => txn_id}

          stub_request(:delete, request_path).with(:query => query)

          Protocol.abort_multipart(@bucket, @object, txn_id)

          expect(WebMock).to have_requested(:delete, request_path)
            .with(:body => nil, :query => query)
        end

        it "should raise Exception on error" do
          txn_id = 'xxxyyyzzz'
          query = {'uploadId' => txn_id}

          code = 'NoSuchUpload'
          message = 'The multipart transaction does not exist.'

          stub_request(:delete, request_path)
            .with(:query => query)
            .to_return(:status => 404, :body => mock_error(code, message))

          expect {
            Protocol.abort_multipart(@bucket, @object, txn_id)
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:delete, request_path)
            .with(:body => nil, :query => query)
        end
      end # abort multipart

      context "List multiparts" do

        it "should GET to list multiparts" do
          request_path = "#{@bucket}.#{@endpoint}/"
          query = {'uploads' => ''}

          stub_request(:get, request_path).with(:query => query)

          Protocol.list_multipart_transactions(@bucket)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
        end

        it "should send extra params when list multiparts" do
          request_path = "#{@bucket}.#{@endpoint}/"
          query = {
            'uploads' => '',
            'prefix' => 'foo-',
            'delimiter' => '-',
            'upload-id-marker' => 'id-marker',
            'key-marker' => 'key-marker',
            'max-uploads' => 10,
            'encoding-type' => KeyEncoding::URL
          }

          stub_request(:get, request_path).with(:query => query)

          Protocol.list_multipart_transactions(
            @bucket,
            :prefix => 'foo-',
            :delimiter => '-',
            :id_marker => 'id-marker',
            :key_marker => 'key-marker',
            :limit => 10,
            :encoding => KeyEncoding::URL
          )

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
        end

        it "should get multipart transactions" do
          request_path = "#{@bucket}.#{@endpoint}/"
          query = {
            'uploads' => '',
            'prefix' => 'foo-',
            'delimiter' => '-',
            'upload-id-marker' => 'id-marker',
            'key-marker' => 'key-marker',
            'max-uploads' => 100,
            'encoding-type' => KeyEncoding::URL
          }

          return_multiparts = (1..5).map do |i|
            Multipart::Transaction.new(
              :id => "id-#{i}",
              :object => "key-#{i}",
              :bucket => @bucket,
              :creation_time => Time.parse(Time.now.rfc822))
          end

          return_more = {
            :prefix => 'foo-',
            :delimiter => '-',
            :id_marker => 'id-marker',
            :key_marker => 'key-marker',
            :next_id_marker => 'next-id-marker',
            :next_key_marker => 'next-key-marker',
            :limit => 100,
            :truncated => true
          }
          stub_request(:get, request_path)
            .with(:query => query)
            .to_return(:body => mock_multiparts(return_multiparts, return_more))

          txns, more = Protocol.list_multipart_transactions(
                  @bucket,
                  :prefix => 'foo-',
                  :delimiter => '-',
                  :id_marker => 'id-marker',
                  :key_marker => 'key-marker',
                  :limit => 100,
                  :encoding => KeyEncoding::URL)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
          expect(txns.map {|x| x.to_s}.join(';'))
            .to eq(return_multiparts.map {|x| x.to_s}.join(';'))
          expect(more).to eq(return_more)
        end

        it "should decode object key" do
          request_path = "#{@bucket}.#{@endpoint}/"
          query = {
            'uploads' => '',
            'prefix' => 'foo-',
            'delimiter' => '-',
            'upload-id-marker' => 'id-marker',
            'key-marker' => 'key-marker',
            'max-uploads' => 100,
            'encoding-type' => KeyEncoding::URL
          }

          return_multiparts = (1..5).map do |i|
            Multipart::Transaction.new(
              :id => "id-#{i}",
              :object => "中国-#{i}",
              :bucket => @bucket,
              :creation_time => Time.parse(Time.now.rfc822))
          end

          es_multiparts = return_multiparts.map do |x|
            Multipart::Transaction.new(
              :id => x.id,
              :object => CGI.escape(x.object),
              :creation_time => x.creation_time)
          end

          return_more = {
            :prefix => 'foo-',
            :delimiter => '中国のruby',
            :id_marker => 'id-marker',
            :key_marker => '杭州のruby',
            :next_id_marker => 'next-id-marker',
            :next_key_marker => '西湖のruby',
            :limit => 100,
            :truncated => true,
            :encoding => KeyEncoding::URL
          }

          es_more = {
            :prefix => 'foo-',
            :delimiter => CGI.escape('中国のruby'),
            :id_marker => 'id-marker',
            :key_marker => CGI.escape('杭州のruby'),
            :next_id_marker => 'next-id-marker',
            :next_key_marker => CGI.escape('西湖のruby'),
            :limit => 100,
            :truncated => true,
            :encoding => KeyEncoding::URL
          }

          stub_request(:get, request_path)
            .with(:query => query)
            .to_return(:body => mock_multiparts(es_multiparts, es_more))

          txns, more = Protocol.list_multipart_transactions(
                  @bucket,
                  :prefix => 'foo-',
                  :delimiter => '-',
                  :id_marker => 'id-marker',
                  :key_marker => 'key-marker',
                  :limit => 100,
                  :encoding => KeyEncoding::URL)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
          expect(txns.map {|x| x.to_s}.join(';'))
            .to eq(return_multiparts.map {|x| x.to_s}.join(';'))
          expect(more).to eq(return_more)
        end

        it "should raise Exception on error" do
          request_path = "#{@bucket}.#{@endpoint}/"
          query = {'uploads' => ''}

          code = 'InvalidArgument'
          message = 'Invalid argument.'
          stub_request(:get, request_path)
            .with(:query => query)
            .to_return(:status => 400, :body => mock_error(code, message))

          expect {
            Protocol.list_multipart_transactions(@bucket)
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
        end
      end # list multiparts

      context "List parts" do

        it "should GET to list parts" do
          txn_id = 'yyyxxxzzz'
          query = {'uploadId' => txn_id}

          stub_request(:get, request_path).with(:query => query)

          Protocol.list_parts(@bucket, @object, txn_id)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
        end

        it "should send extra params when list parts" do
          txn_id = 'yyyxxxzzz'
          query = {
            'uploadId' => txn_id,
            'part-number-marker' => 'foo-',
            'max-parts' => 100,
            'encoding-type' => KeyEncoding::URL
          }

          stub_request(:get, request_path).with(:query => query)

          Protocol.list_parts(@bucket, @object, txn_id,
                          :marker => 'foo-',
                          :limit => 100,
                          :encoding => KeyEncoding::URL)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
        end

        it "should get parts" do
          txn_id = 'yyyxxxzzz'
          query = {
            'uploadId' => txn_id,
            'part-number-marker' => 'foo-',
            'max-parts' => 100,
            'encoding-type' => KeyEncoding::URL
          }

          return_parts = (1..5).map do |i|
            Multipart::Part.new(
              :number => i,
              :etag => "etag-#{i}",
              :size => 1024,
              :last_modified => Time.parse(Time.now.rfc822))
          end

          return_more = {
            :marker => 'foo-',
            :next_marker => 'bar-',
            :limit => 100,
            :truncated => true
          }

          stub_request(:get, request_path)
            .with(:query => query)
            .to_return(:body => mock_parts(return_parts, return_more))

          parts, more = Protocol.list_parts(@bucket, @object, txn_id,
                          :marker => 'foo-',
                          :limit => 100,
                          :encoding => KeyEncoding::URL)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
          part_numbers = return_parts.map {|x| x.number}
          expect(parts.map {|x| x.number}).to match_array(part_numbers)
          expect(more).to eq(return_more)
        end

        it "should raise Exception on error" do
          txn_id = 'yyyxxxzzz'
          query = {'uploadId' => txn_id}

          code = 'InvalidArgument'
          message = 'Invalid argument.'

          stub_request(:get, request_path)
            .with(:query => query)
            .to_return(:status => 400, :body => mock_error(code, message))

          expect {
            Protocol.list_parts(@bucket, @object, txn_id)
          }.to raise_error(Exception, message)

          expect(WebMock).to have_requested(:get, request_path)
            .with(:body => nil, :query => query)
        end
      end # list parts

    end # Multipart

  end # OSS
end # Aliyun
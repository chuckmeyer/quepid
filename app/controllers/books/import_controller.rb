# frozen_string_literal: true

require 'open-uri'
require 'json'

require 'action_view'

module Books
  class ImportController < ApplicationController
    include ActionView::Helpers::NumberHelper
    def new
      @book = Book.new
    end

    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Security/Open
    # rubocop:disable Metrics/AbcSize
    def create
      @book = Book.new
      @book.owner = current_user

      uploaded_file = params[:book][:import_file]
      json_file = uploaded_file.tempfile
      json_data = URI.open(json_file) do |file|
        JSON.parse(file.read)
      end

      begin
        params_to_use = JSON.parse(json_data.read).deep_symbolize_keys

        @book.name = params_to_use[:name]

        service = ::BookImporter.new @book, params_to_use, {}
        service.validate
      rescue JSON::ParserError => e
        @book.errors.add(:base, "Invalid JSON file format: #{e.message}")
      end

      if @book.errors.empty? && @book.save
        serialized_data = Marshal.dump(params_to_use)
        puts "the size of the serialized data is #{number_to_human_size(serialized_data.bytesize)}"
        compressed_data = Zlib::Deflate.deflate(serialized_data)
        puts "the size of the compressed data is #{number_to_human_size(compressed_data.bytesize)}"
        @book.import_file.attach(io: StringIO.new(compressed_data), filename: "book_import_#{@book.id}.bin.zip",
                                 content_type: 'application/zip')
        @book.save
        ImportBookJob.perform_later @book
        redirect_to @book, notice: 'Book was successfully created.'
      else
        render :new
      end
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Security/Open
    # rubocop:enable Metrics/AbcSize
  end
end

# frozen_string_literal: true

require "lumberjack_json_device"

module Lumberjack
  # This Lumberjack device logs output to another device as JSON formatted text that maps fields
  # to the standard ECS JSON format.
  #
  # See https://www.elastic.co/guide/en/ecs/current/ecs-field-reference.html
  class EcsDevice < JsonDevice
    module ExceptionHash
      protected

      def exception_hash(exception, device)
        hash = {"type" => exception.class.name}
        hash["message"] = exception.message unless exception.message.nil?
        trace = exception.backtrace
        if trace && device&.respond_to?(:backtrace_cleaner) && device.backtrace_cleaner
          trace = device.backtrace_cleaner.call(trace)
        end
        hash["stack_trace"] = trace if trace
        hash
      end
    end

    # Formatter to format a messge as an error if it is an exception.
    class MessageExceptionFormatter
      include ExceptionHash

      def initialize(device = nil)
        @device = device
      end

      def call(object)
        if object.is_a?(Exception)
          {
            "message" => object.inspect,
            "error" => exception_hash(object, @device)
          }
        elsif object.is_a?(Hash)
          {"message" => object}
        elsif object.nil?
          {"message" => nil}
        else
          message = object.to_s
          max_message_length = @device.max_message_length
          if max_message_length && message.length > max_message_length
            message = message[0, max_message_length]
          end
          {"message" => message}
        end
      end
    end

    # Formatter to remove empty tag values and expand the error tag if it is an exception.
    class EcsTagsFormatter
      include ExceptionHash

      def initialize(device = nil)
        @device = device
      end

      def call(tags)
        copy = {}
        tags.each do |name, value|
          value = remove_empty_values(value)
          next if value.nil?

          if name == "error" && value.is_a?(Exception)
            copy[name] = exception_hash(value, @device)
          elsif name.include?(".")
            names = name.split(".")
            next_value_in_hash(copy, names, value)
          else
            copy[name] = value
          end
        end
        copy
      end

      private

      def remove_empty_values(value)
        if value.is_a?(String)
          value unless value.empty?
        elsif value.is_a?(Hash)
          new_hash = {}
          value.each do |key, val|
            val = remove_empty_values(val)
            new_hash[key] = val unless val.nil?
          end
          new_hash unless new_hash.empty?
        elsif value.is_a?(Array)
          new_array = value.collect { |val| remove_empty_values(val) }
          new_array unless new_array.empty?
        else
          value
        end
      end

      def next_value_in_hash(hash, keys, value)
        key = keys.first
        if keys.size == 1
          hash[key] = value
        else
          current = hash[key]
          unless current.is_a?(Hash)
            current = {}
            hash[key] = current
          end
          next_value_in_hash(current, keys[1, keys.size], value)
        end
      end
    end

    class DurationFormatter
      def initialize(multiplier)
        @multiplier = multiplier
      end

      def call(value)
        if value.is_a?(Numeric)
          value = (value.to_f * @multiplier).round
        end
        {"event" => {"duration" => value}}
      end
    end

    ECS_TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%S.%6NZ"

    # You can specify a backtrace cleaner that will be called with exception backtraces before they
    # are added to the payload. You can use this to remove superfluous lines, compress line length, etc.
    # One use for it is to keep stack traces clean and prevent them from overflowing the limit on
    # the payload size for an individual log entry.
    attr_accessor :backtrace_cleaner

    # You can specify a limit on the message size. Messages over this size will be split into multiple
    # log entries to prevent overflowing the limit on message size which makes the log entries unparseable.
    attr_accessor :max_message_length

    def initialize(stream_or_device, backtrace_cleaner: nil, max_message_length: nil, datetime_format: ECS_TIMESTAMP_FORMAT)
      super(stream_or_device, mapping: ecs_mapping, datetime_format: datetime_format)
      self.backtrace_cleaner = backtrace_cleaner
      self.max_message_length = max_message_length
      @utc_timestamps = !!datetime_format.match(/[^%]Z/)
    end

    def entry_as_json(entry)
      original_time = entry.time
      begin
        entry.time = entry.time.utc if @utc_timestamps && !entry.time.utc?
        super
      ensure
        entry.time = original_time
      end
    end

    private

    def ecs_mapping
      {
        time: "@timestamp",
        severity: ["log", "level"],
        progname: ["process", "name"],
        pid: ["process", "pid"],
        message: MessageExceptionFormatter.new(self),
        duration: DurationFormatter.new(1_000_000_000),
        duration_ms: DurationFormatter.new(1_000_000),
        duration_micros: DurationFormatter.new(1_000),
        duration_ns: ["event", "duration"],
        tags: EcsTagsFormatter.new(self)
      }
    end
  end
end

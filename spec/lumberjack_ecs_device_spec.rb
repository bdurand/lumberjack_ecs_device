require "spec_helper"

describe Lumberjack::EcsDevice do
  let(:device) { Lumberjack::EcsDevice.new(output) }
  let(:output) { StringIO.new }

  describe "entry_as_json" do
    it "should output the fields the ECS format" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => "boo")
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "log" => {"level" => entry.severity_label},
        "process" => {"name" => entry.progname, "pid" => entry.pid},
        "message" => entry.message,
        "foo" => "bar",
        "baz" => "boo"
      })
    end

    it "should not include empty tags" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", nil, 12345, {})
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "log" => {"level" => entry.severity_label},
        "process" => {"pid" => entry.pid},
        "message" => entry.message
      })
    end

    it "should convert dot notated tags to nested JSON" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", nil, nil, "http.response.status_code" => 200, "http.request.method" => "GET")
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "log" => {"level" => entry.severity_label},
        "message" => entry.message,
        "http" => {
          "response" => {"status_code" => 200},
          "request" => {"method" => "GET"}
        }
      })
    end

    describe "exceptions" do
      it "should format the message as an error if it is an exception" do
        error = nil
        begin
          raise "boom"
        rescue => e
          error = e
        end

        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, error, nil, nil, {})
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => error.inspect,
          "error" => {
            "type" => "RuntimeError",
            "message" => "boom",
            "stack_trace" => error.backtrace
          }
        })
      end

      it "should expand the error tag if it is an exception" do
        error = nil
        begin
          raise "boom"
        rescue => e
          error = e
        end

        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "an error occurred", nil, nil, "error" => error)
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "error" => {
            "type" => "RuntimeError",
            "message" => "boom",
            "stack_trace" => error.backtrace
          }
        })
      end

      it "should not expand the error tag if it is not an exception" do
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "an error occurred", nil, nil, "error" => "error string")
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "error" => "error string"
        })
      end

      it "should call the backtrace cleaner on message exceptions" do
        device.backtrace_cleaner = lambda { |trace| ["redacted"] }
        error = nil
        begin
          raise "boom"
        rescue => e
          error = e
        end

        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, error, nil, nil, {})
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => error.inspect,
          "error" => {
            "type" => "RuntimeError",
            "message" => "boom",
            "stack_trace" => ["redacted"]
          }
        })
      end

      it "should call the backtrace cleaner on the error tag exception" do
        device.backtrace_cleaner = lambda { |trace| ["redacted"] }
        error = nil
        begin
          raise "boom"
        rescue => e
          error = e
        end

        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "an error occurred", nil, nil, "error" => error)
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "error" => {
            "type" => "RuntimeError",
            "message" => "boom",
            "stack_trace" => ["redacted"]
          }
        })
      end

      it "should handle exception message without a backtrace" do
        error = RuntimeError.new("boom")
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, error, nil, nil, {})
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => error.inspect,
          "error" => {
            "type" => "RuntimeError",
            "message" => "boom"
          }
        })
      end

      it "should handle error tag exceptions without a backtrace" do
        error = RuntimeError.new("boom")
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "an error occurred", nil, nil, "error" => error)
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "error" => {
            "type" => "RuntimeError",
            "message" => "boom"
          }
        })
      end
    end

    describe "duration" do
      it "should convert duration from seconds to nanoseconds" do
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", nil, nil, "duration" => 1.2)
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "event" => {"duration" => 1_200_000_000}
        })
      end

      it "should convert duration_ms from milliseconds to nanoseconds" do
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", nil, nil, "duration_ms" => 1200)
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "event" => {"duration" => 1_200_000_000}
        })
      end

      it "should convert duration_ns from microseconds to nanoseconds" do
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", nil, nil, "duration_micros" => 1200)
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "event" => {"duration" => 1_200_000}
        })
      end

      it "should convert duration_ns from milliseconds to nanoseconds" do
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", nil, nil, "duration_ns" => 12000)
        data = device.entry_as_json(entry)
        expect(data).to eq({
          "@timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "log" => {"level" => entry.severity_label},
          "message" => entry.message,
          "event" => {"duration" => 12000}
        })
      end
    end
  end
end

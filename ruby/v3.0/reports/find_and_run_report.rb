#!/usr/bin/env ruby
# Encoding: utf-8
#
# Copyright (C) 2016 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# An end-to-end example of how to find and run a report.

require_relative '../dfareporting_utils'

# The following values control retry behavior while the report is processing.
# Minimum amount of time between polling requests. Defaults to 10 seconds.
MIN_RETRY_INTERVAL = 10
# Maximum amount of time between polling requests. Defaults to 10 minutes.
MAX_RETRY_INTERVAL = 10 * 60
# Maximum amount of time to spend polling. Defaults to 1 hour.
MAX_RETRY_ELAPSED_TIME = 60 * 60

def find_and_run_report(profile_id)
  # Authenticate and initialize API service.
  service = DfareportingUtils.get_service()

  # 1. Find a report to run.
  report = find_report(service, profile_id)

  if report
    # 2. Run the report.
    report_file = run_report(service, profile_id, report.id)

    # 3. Wait for the report file to be ready.
    wait_for_report_file(service, report.id, report_file.id)
  else
    puts "No report found for profile ID %d." % profile_id
  end
end

def find_report(service, profile_id)
  page_token = nil
  target = nil

  begin
    result = service.list_reports(profile_id, {:page_token => page_token})

    result.items.each do |report|
      if is_target_report(report)
        target = report
        break
      end
    end

    if target.nil? and result.items.any?
      page_token = result.next_page_token
    else
      page_token = nil
    end
  end until page_token.to_s.empty?

  if target
    puts 'Found report %s with filename "%s".' % [target.id, target.file_name]
    return target
  end

  puts 'Unable to find report for profile ID %d.' % profile_id
  return nil
end

def is_target_report(report)
  # Provide custom validation logic here.
  # For example purposes, any report is considered valid.
  return !report.nil?
end

def run_report(service, profile_id, report_id)
  # Run the report.
  report_file = service.run_report(profile_id, report_id)

  puts 'Running report %d, current file status is %s.' %
      [report_id, report_file.status]
  return report_file
end

def wait_for_report_file(service, report_id, file_id)
  # Wait for the report file to finish processing.
  # An exponential backoff strategy is used to conserve request quota.
  interval = 0
  start_time = Time.now
  loop do
    report_file = service.get_file(report_id, file_id)

    status = report_file.status
    if status == 'REPORT_AVAILABLE'
      puts 'File status is %s, ready to download.' % status
      break
    elsif status != 'PROCESSING'
      puts 'File status is %s, processing failed.' % status
      break
    elsif Time.now - start_time > MAX_RETRY_ELAPSED_TIME
      puts 'File processing deadline exceeded.'
      break
    end

    interval = next_sleep_interval(interval)
    puts 'File status is %s, sleeping for %d seconds.' % [status, interval]
    sleep(interval)
  end
end

def next_sleep_interval(previous_interval)
  min_interval = [MIN_RETRY_INTERVAL, previous_interval].max
  max_interval = [MIN_RETRY_INTERVAL, previous_interval * 3].max
  return [MAX_RETRY_INTERVAL, rand(min_interval..max_interval)].min
end

if __FILE__ == $0
  # Retrieve command line arguments.
  args = DfareportingUtils.get_arguments(ARGV, :profile_id)

  find_and_run_report(args[:profile_id])
end

#
# Author:: Dell Cloud Manager OSS
# Copyright:: Dell, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "chef"
require "chef/handler"

begin
  require "slackr"
rescue LoadError
  Chef::Log.debug("Chef slack_handler requires `slackr` gem")
end

require "timeout"

class Chef::Handler::Slack < Chef::Handler
  attr_reader :team, :api_key, :config, :timeout, :fail_only

  def initialize(config = {})
    @config  = config.dup
    @team    = @config.delete(:team)
    @api_key = @config.delete(:api_key)
    @timeout = @config.delete(:timeout) || 15
    @fail_only = @config.delete(:fail_only) || false
    @config.delete(:icon_emoji) if @config[:icon_url] && @config[:icon_emoji]
  end

  def report
    unless fail_only && run_status.success?
      begin
        updated_resources = run_status.updated_resources.nil? ? 0 : run_status.updated_resources.length
        all_resources = run_status.all_resources.nil? ? 0 : run_status.all_resources.length
        Timeout::timeout(@timeout) do
          Chef::Log.debug("Sending report to Slack #{config[:channel]}@#{team}.slack.com")
          message = "Chef run on #{run_status.node.name} #{run_status_human_readable}"
          attachment = {}
          attachment[:color] = run_status.success? ? "#458B00" : "#FF0000"
          attachment[:fields] = []
          attachment[:fields] << {
            title: "Updated Resources",
            value: updated_resources,
            short: true
          }
          attachment[:fields] << {
            title: "Total Resources",
            value: all_resources,
            short: true
          }
          unless run_status.success?
            if run_status.updated_resources.length > 0
              attachment[:fields] << {
                title: "Updated Resources",
                value: run_status.updated_resources.join("\n"),
                short: false
              }
            end
            attachment[:fields] << {
              title: "Exception",
              value: run_status.formatted_exception,
              short: false
            }
          end
          slack_message(message, attachment)
        end
      rescue Exception => e
        Chef::Log.debug("Failed to send message to Slack: #{e.message}")
      end
    end
  end

  private

  def slack_message(content, options = {})
    slack = Slackr::Webhook.new(team, api_key, config)
    slack.say(content, options)
  end

  def run_status_human_readable
    run_status.success? ? "succeeded." : "FAILED!"
  end
end


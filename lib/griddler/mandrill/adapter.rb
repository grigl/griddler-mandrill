module Griddler
  module Mandrill
    class Adapter
      def initialize(params)
        @params = params
      end

      def self.normalize_params(params)
        adapter = new(params)
        adapter.normalize_params
      end

      def normalize_params
        events.select do |event|
          event[:spf].present? && (event[:spf][:result] == 'pass' || event[:spf][:result] == 'neutral')
        end.map do |event|
          {
            to: to(event),
            cc: recipients(:cc, event) || [],
            bcc: resolve_bcc(event),
            headers: headers(event),
            from: from(event),
            subject: event[:subject] || '',
            text: text(event),
            html: html(event),
            raw_body: event[:raw_msg],
            attachments: attachment_files(event),
            email: event[:email] || '' # the email address where Mandrill received the message
          }
        end
      end

      private

      attr_reader :params

      def text(event)
        mail_obj = Mail.new(event[:raw_msg])
        if strange_email?(event)
          mail_obj.text_part.decode_body.force_encoding('utf-8')
        elsif mail_obj.text_part.present?
          event[:text]
        else
          ''
        end
      end

      def html(event)
        mail_obj = Mail.new(event[:raw_msg])
        if strange_email?(event)
          mail_obj.html_part.decode_body.force_encoding('utf-8')
        elsif mail_obj.html_part.present?
          event[:html]
        else
          ''
        end
      end

      def to(event)
        recipients = recipients(:to, event)
        if recipients.present?
          recipients
        elsif event[:email]
          [event[:email]]
        else
          []
        end
      end

      def from(event)
        if event[:from_email]
          full_email([event[:from_email], event[:from_name]])
        else
          Mail.new(event[:raw_msg]).from[0]
        end
      end

      def headers(event)
        headers = event[:headers]
        if headers.present?
          headers
        else
          {}
        end
      end

      def strange_email?(event)
        !event[:headers].present? || !event[:to].present?
      end

      def events
        @events ||= ActiveSupport::JSON.decode(params[:mandrill_events]).map { |event|
          event['msg'].with_indifferent_access if event['event'] == 'inbound'
        }.compact
      end

      def recipients(field, event)
        Array.wrap(event[field]).map { |recipient| full_email(recipient) }
      end

      def resolve_bcc(event)
        email = event[:email]
        if event[:to] && !event[:to].map(&:first).include?(email) && event[:cc] && !event[:cc].map(&:first).include?(email)
          [full_email([email, email.split("@")[0]])]
        else
          []
        end
      end

      def full_email(contact_info)
        email = contact_info[0]
        if contact_info[1]
          "#{contact_info[1]} <#{email}>"
        elsif email
          email
        else
          ''
        end
      end

      def attachment_files(event)
        attachments = event[:attachments] || Array.new
        attachments.map do |key, attachment|
          ActionDispatch::Http::UploadedFile.new({
            filename: attachment[:name],
            type: attachment[:type],
            tempfile: create_tempfile(attachment)
          })
        end
      end

      def create_tempfile(attachment)
        filename = attachment[:name].gsub(/\/|\\/, '_')
        tempfile = Tempfile.new(filename, Dir::tmpdir, encoding: 'ascii-8bit')
        content = attachment[:content]
        content = Base64.decode64(content) if attachment[:base64]
        tempfile.write(content)
        tempfile.rewind
        tempfile
      end
    end
  end
end

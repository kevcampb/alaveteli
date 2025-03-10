class OutgoingMessage
  module Template
    class IncomingMessageFollowup
      def body(opts = {})
        assert_required_keys(opts, :public_body_name)
        template_string(opts)
      end

      def salutation(replacements = {})
        _("Dear {{public_body_name}},", replacements)
      end

      def letter(replacements = {})
        if replacements[:letter]
          "\n\n#{ replacements[:letter] }"
        else
          ''
        end
      end

      def signoff(replacements = {})
        _("Yours sincerely,", replacements)
      end

      private

      def template_string(replacements)
        msg = salutation(replacements)
        msg += letter(replacements)
        msg += "\n\n\n\n"
        msg += signoff(replacements)
        msg += "\n\n"
      end

      def assert_required_keys(hash, *required_keys)
        required_keys.each do |required_key|
          unless hash.key?(required_key)
            raise ArgumentError, "Missing required key: #{required_key}"
          end
        end
      end
    end
  end
end

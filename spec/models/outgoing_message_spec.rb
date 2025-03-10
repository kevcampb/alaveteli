# == Schema Information
# Schema version: 20210114161442
#
# Table name: outgoing_messages
#
#  id                           :integer          not null, primary key
#  info_request_id              :integer          not null
#  body                         :text             not null
#  status                       :string           not null
#  message_type                 :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  last_sent_at                 :datetime
#  incoming_message_followup_id :integer
#  what_doing                   :string           not null
#  prominence                   :string           default("normal"), not null
#  prominence_reason            :text
#

require 'spec_helper'
require 'models/concerns/message_prominence'
require 'models/concerns/taggable'

RSpec.describe OutgoingMessage do
  it_behaves_like 'concerns/message_prominence', :initial_request
  it_behaves_like 'concerns/taggable', :initial_request

  describe '.is_searchable' do
    subject { described_class.is_searchable }

    let!(:searchable_message) { FactoryBot.create(:initial_request) }
    let!(:unsearchable_message) { FactoryBot.create(:initial_request, :hidden) }

    it { is_expected.to include(searchable_message) }
    it { is_expected.not_to include(unsearchable_message) }
  end

  describe '.followup' do
    subject { described_class.followup }

    let!(:followup_message) { FactoryBot.create(:new_information_followup) }
    let!(:initial_message) { FactoryBot.create(:initial_request) }

    it { is_expected.to include(followup_message) }
    it { is_expected.not_to include(initial_message) }
  end

  describe '.fill_in_salutation' do

    it 'replaces the batch request salutation with the body name' do
      text = 'Dear [Authority name],'
      public_body = FactoryBot.build(:public_body, name: 'A Body')
      expect(described_class.fill_in_salutation(text, public_body)).
        to eq('Dear A Body,')
    end

  end

  describe '.with_body' do

    let(:message) { FactoryBot.create(:initial_request, body: "foo\r\nbar") }

    it 'should return message if body matches exactly' do
      expect(OutgoingMessage.with_body("foo\r\nbar")).to include(message)
    end

    context 'when using PostgreSQL database' do

      before do
        if ActiveRecord::Base.connection.adapter_name != 'PostgreSQL'
          skip 'These tests only work for PostgreSQL'
        end
      end

      it 'should match message body when whitespace is ignored' do
        expect(OutgoingMessage.with_body('foobar')).to include(message)
        expect(OutgoingMessage.with_body('foo bar')).to include(message)
        expect(OutgoingMessage.with_body("foo\nbar")).to include(message)
      end

      it 'should match whole message body' do
        expect(OutgoingMessage.with_body('foo')).to_not include(message)
        expect(OutgoingMessage.with_body('foobarbaz')).to_not include(message)
        expect(OutgoingMessage.with_body('foo bar baz')).to_not include(message)
        expect(OutgoingMessage.with_body("foo\nbar\nbaz")).to_not include(message)
        expect(OutgoingMessage.with_body("foo\r\nbar\r\nbaz")).to_not include(message)
      end

    end

  end

  describe '.expected_send_errors' do
    subject { described_class.expected_send_errors }
    class TestError < StandardError; end

    it { is_expected.to be_an(Array) }
    it { is_expected.to include(IOError) }
    it { is_expected.to_not include(TestError) }

    context '.additional_send_errors has been overriden to include a custom error' do
      before do
        allow(described_class).to receive(:additional_send_errors).
          and_return([ TestError ])
      end

      it { is_expected.to include(TestError) }
    end

  end

  describe '#initialize' do

    it 'does not censor the #body' do
      attrs = { status: 'ready',
                message_type: 'initial_request',
                body: 'abc',
                what_doing: 'normal_sort' }

      message = FactoryBot.create(:outgoing_message, attrs)

      expect_any_instance_of(OutgoingMessage).not_to receive(:body).and_call_original
      OutgoingMessage.find(message.id)
    end

  end

  describe '#default_letter' do

    it 'reloads the default body when set after initialization' do
      req = FactoryBot.build(:info_request)
      message = described_class.new(info_request: req)
      message.default_letter = 'test'
      expect(message.body).to include('test')
    end

    it 'does not replace the body if it has already been changed' do
      req = FactoryBot.build(:info_request)
      message = described_class.new(info_request: req)
      message.body = 'toast'
      message.default_letter = 'test'
      expect(message.body).not_to include('test')
    end

  end

  describe '#what_doing' do

    it 'allows a value of normal_sort' do
      message =
        FactoryBot.build(:initial_request, what_doing: 'normal_sort')
      expect(message).to be_valid
    end

    it 'allows a value of internal_review' do
      message =
        FactoryBot.build(:initial_request, what_doing: 'internal_review')
      expect(message).to be_valid
    end

    it 'allows a value of external_review' do
      message =
        FactoryBot.build(:initial_request, what_doing: 'external_review')
      expect(message).to be_valid
    end

    it 'allows a value of new_information' do
      message =
        FactoryBot.build(:initial_request, what_doing: 'new_information')
      expect(message).to be_valid
    end

    it 'adds an error to :what_doing_dummy if an invalid value is provided' do
      message = FactoryBot.build(:initial_request, what_doing: 'invalid')
      message.valid?
      expect(message.errors[:what_doing_dummy]).
        to eq(['Please choose what sort of reply you are making.'])
    end

  end

  describe '#destroy' do
    it 'should destroy the outgoing message' do
      attrs = { status: 'ready',
                message_type: 'initial_request',
                body: 'abc',
                what_doing: 'normal_sort' }
      outgoing_message = FactoryBot.create(:outgoing_message, attrs)
      outgoing_message.destroy
      expect(OutgoingMessage.where(id: outgoing_message.id)).to be_empty
    end

    it 'should destroy the associated info_request_events' do
      info_request = FactoryBot.create(:info_request)
      outgoing_message = info_request.outgoing_messages.first
      outgoing_message.destroy
      expect(InfoRequestEvent.where(outgoing_message_id: outgoing_message.id)).to be_empty
    end
  end

  describe '#from' do

    it 'uses the user name and request magic email' do
      user = FactoryBot.create(:user, name: 'Spec User 862')
      request = FactoryBot.create(:info_request, user: user)
      message = FactoryBot.build(:initial_request, info_request: request)
      expected = "Spec User 862 <request-#{ request.id }-#{ request.idhash }@localhost>"
      expect(message.from).to eq(expected)
    end

  end

  describe '#to' do

    context 'when sending an initial request' do

      it 'uses the public body name and email' do
        body = FactoryBot.create(:public_body, name: 'Example Public Body',
                                               short_name: 'EPB')
        request = FactoryBot.create(:info_request, public_body: body)
        message = FactoryBot.build(:initial_request, info_request: request)
        expected = 'FOI requests at EPB <request@example.com>'
        expect(message.to).to eq(expected)
      end

    end

    context 'when following up to an incoming message' do

      it 'uses the safe_from_name if the incoming message has a valid address' do
        message = FactoryBot.build(:internal_review_request)

        followup =
          mock_model(IncomingMessage, from_email: 'specific@example.com',
                                      safe_from_name: 'Specific Person',
                                      valid_to_reply_to?: true)
        allow(message).to receive(:incoming_message_followup).and_return(followup)

        expected = 'Specific Person <specific@example.com>'
        expect(message.to).to eq(expected)
      end

      it 'uses the public body address if the incoming message has an invalid address' do
        body = FactoryBot.create(:public_body, name: 'Example Public Body',
                                               short_name: 'EPB')
        request = FactoryBot.create(:info_request, public_body: body)
        message = FactoryBot.build(:new_information_followup,
                                   info_request: request)

        followup =
          mock_model(IncomingMessage, from_email: 'invalid@example',
                                      safe_from_name: 'Specific Person',
                                      valid_to_reply_to?: false)
        allow(message).to receive(:incoming_message_followup).and_return(followup)

        expected = 'FOI requests at EPB <request@example.com>'
        expect(message.to).to eq(expected)
      end

    end

  end

  describe '#subject' do

    context 'when sending an initial request' do

      it 'uses the request title with the law prefixed' do
        request = FactoryBot.create(:info_request, title: 'Example Request')
        message = FactoryBot.build(:initial_request, info_request: request)
        expected = 'Freedom of Information request - Example Request'
        expect(message.subject).to eq(expected)
      end

    end

    context 'when sending a followup that is not a reply to an incoming message' do

      it 'prefixes the initial request subject with Re:' do
        request = FactoryBot.create(:info_request, title: 'Example Request')
        message = FactoryBot.build(:new_information_followup,
                                   info_request: request)
        allow(message).to receive(:incoming_message_followup).and_return(nil)
        expected = 'Re: Freedom of Information request - Example Request'
        expect(message.subject).to eq(expected)
      end

    end

    context 'when following up to an incoming message' do

      it 'uses the request title prefixed with Re: if the incoming message does not have a valid reply address' do
        request = FactoryBot.create(:info_request, title: 'Example Request')
        message = FactoryBot.build(:new_information_followup,
                                   info_request: request)

        followup =
          mock_model(IncomingMessage, valid_to_reply_to?: false)
        allow(message).
          to receive(:incoming_message_followup).and_return(followup)

        expected = 'Re: Freedom of Information request - Example Request'
        expect(message.subject).to eq(expected)
      end

      it 'uses the request title prefixed with Re: if the incoming message does not have a subject' do
        request = FactoryBot.create(:info_request, title: 'Example Request')
        message = FactoryBot.build(:new_information_followup,
                                   info_request: request)

        followup = mock_model(IncomingMessage, subject: nil,
                                               valid_to_reply_to?: true)
        allow(message).
          to receive(:incoming_message_followup).and_return(followup)

        expected = 'Re: Freedom of Information request - Example Request'
        expect(message.subject).to eq(expected)
      end

      it 'uses the incoming message subject if it is already prefixed with Re:' do
        request = FactoryBot.create(:info_request, title: 'Example Request')
        message = FactoryBot.build(:new_information_followup,
                                   info_request: request)

        followup =
          mock_model(IncomingMessage, valid_to_reply_to?: true,
                                      subject: 'Re: FOI REF#123456789')
        allow(message).
          to receive(:incoming_message_followup).and_return(followup)

        expect(message.subject).to eq('Re: FOI REF#123456789')
      end

      it 'prefixes the incoming message subject if it is not prefixed with Re:' do
        request = FactoryBot.create(:info_request, title: 'Example Request')
        message = FactoryBot.build(:new_information_followup,
                                   info_request: request)

        followup =
          mock_model(IncomingMessage, valid_to_reply_to?: true,
                                      subject: 'FOI REF#123456789')
        allow(message).
          to receive(:incoming_message_followup).and_return(followup)

        expect(message.subject).to eq('Re: FOI REF#123456789')
      end

    end

    context 'when requesting an internal review' do

      it 'prefixes the request title with the internal review message' do
        request = FactoryBot.create(:info_request, title: 'Example Request')
        message = FactoryBot.build(:internal_review_request, info_request: request)
        expected = 'Internal review of Freedom of Information request - Example Request'
        expect(message.subject).to eq(expected)
      end

    end

  end

  describe '#body' do

    it 'returns the body attribute' do
      attrs = { status: 'ready',
                message_type: 'initial_request',
                body: 'abc',
                what_doing: 'normal_sort' }

      message = FactoryBot.build(:outgoing_message, attrs)
      expect(message.body).to eq('abc')
    end

    it 'strips the body of leading and trailing whitespace' do
      attrs = { status: 'ready',
                message_type: 'initial_request',
                body: ' abc ',
                what_doing: 'normal_sort' }

      message = FactoryBot.build(:outgoing_message, attrs)
      expect(message.body).to eq('abc')
    end

    it 'removes excess linebreaks that unnecessarily space it out' do
      attrs = { status: 'ready',
                message_type: 'initial_request',
                body: "ab\n\nc\n\n",
                what_doing: 'normal_sort' }

      message = FactoryBot.build(:outgoing_message, attrs)
      expect(message.body).to eq("ab\n\nc")
    end

    it "applies the associated request's censor rules to the text" do
      attrs = { status: 'ready',
                message_type: 'initial_request',
                body: 'This sensitive text contains secret info!',
                what_doing: 'normal_sort' }
      message = FactoryBot.build(:outgoing_message, attrs)

      rules = [FactoryBot.build(:censor_rule, text: 'secret'),
               FactoryBot.build(:censor_rule, text: 'sensitive')]
      allow_any_instance_of(InfoRequest).to receive(:censor_rules).and_return(rules)

      expected = 'This [REDACTED] text contains [REDACTED] info!'
      expect(message.body).to eq(expected)
    end

    it "applies the given censor rules to the text" do
      attrs = { status: 'ready',
                message_type: 'initial_request',
                body: 'This sensitive text contains secret info!',
                what_doing: 'normal_sort' }
      message = FactoryBot.build(:outgoing_message, attrs)

      request_rules = [FactoryBot.build(:censor_rule, text: 'secret'),
                       FactoryBot.build(:censor_rule, text: 'sensitive')]
      allow_any_instance_of(InfoRequest).to receive(:censor_rules).and_return(request_rules)

      censor_rules = [FactoryBot.build(:censor_rule, text: 'text'),
                      FactoryBot.build(:censor_rule, text: 'contains')]

      expected = 'This sensitive [REDACTED] [REDACTED] secret info!'
      expect(message.body(censor_rules: censor_rules)).to eq(expected)
    end

    context "validation" do
      let(:public_body) do
        FactoryBot.create(:public_body, name: 'a test public body')
      end

      let(:info_request) do
        FactoryBot.create(:info_request,
                          public_body: public_body,
                          url_title: 'a_test_title',
                          title: 'A test title')
      end

      it "adds an error message if the text has not been changed" do
        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'initial_request',
                              what_doing: 'normal_sort',
                              info_request: info_request)

        outgoing_message.valid?
        expect(outgoing_message.errors.messages[:body]).
          to include("Please enter your letter requesting information")
      end

      it "adds an error message if the signature block is incomplete" do
        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'initial_request',
                              what_doing: 'normal_sort',
                              info_request: info_request)

        outgoing_message.valid?
        expect(outgoing_message.errors.messages[:body]).
          to include("Please sign at the bottom with your name, or alter the " \
                     "\"Yours faithfully,\" signature")
      end

      it "does not add the 'enter your letter' error if the text has been changed" do
        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'initial_request',
                              what_doing: 'normal_sort',
                              info_request: info_request)

        outgoing_message.body = "Dear a test public body,\n\nI would like some information please.\n\nYours faithfully,\n\n"

        outgoing_message.valid?
        expect(outgoing_message.errors.messages[:body]).
          not_to include("Please enter your letter requesting information")
      end

      it "can cope with HTML entities in the message body" do
        test_body = FactoryBot.create(:public_body,
                                      name: "D's Test Authority")

        info_request = FactoryBot.create(:info_request,
                                         public_body: test_body,
                                         url_title: 'a_test_title',
                                         title: 'A test title')

        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'initial_request',
                              what_doing: 'normal_sort',
                              info_request: info_request)

        outgoing_message.valid?
        expect(outgoing_message.errors.messages[:body]).
          not_to include("Please enter your letter requesting information")
      end

      context "when default_letter text has been set" do
        before(:each) do
          allow_any_instance_of(OutgoingMessage).to receive(:default_letter).
            and_return("\n\nIn accordance with Regulation 1049/2001\n\n")
        end

        let(:outgoing_message) do
          OutgoingMessage.new(status: 'ready',
                              message_type: 'initial_request',
                              what_doing: 'normal_sort',
                              info_request: info_request)
        end

        it "adds the default_letter text to the message body" do
          expect(outgoing_message.body).
            to include("In accordance with Regulation 1049/2001")
        end

        it "adds an error message if the text has not been changed" do
          outgoing_message.valid?
          expect(outgoing_message.errors.messages[:body]).
            to include("Please enter your letter requesting information")
        end

        it "is not fooled by changes to the line spacing" do
          outgoing_message.body = "Dear a test public body,\n\n  In accordance with Regulation 1049/2001\n\n\n\n\n\nYours faithfully,"

          outgoing_message.valid?
          expect(outgoing_message.errors.messages[:body]).
            to include("Please enter your letter requesting information")
        end

        it "does not break when given a mix of linebreak encodings" do
          outgoing_message.body = "Dear a test public body,\r\nIn accordance with Regulation 1049/2001\r\nYours faithfully,"

          outgoing_message.valid?
          expect(outgoing_message.errors.messages[:body]).
            to include("Please enter your letter requesting information")
        end

        context "when a censor rule changes the default text" do

          before do
            opts = { text: 'Regulation 1049/2001',
                   replacement: 'the law',
                   last_edit_editor: 'unknown',
                   last_edit_comment: 'none' }
            CensorRule.create!(opts)

            outgoing_message.apply_masks(outgoing_message.body, 'text/plain')
          end

          it "copes with a global censor rule that affects the default text" do
            outgoing_message.valid?
            expect(outgoing_message.errors.messages[:body]).
              to include("Please enter your letter requesting information")
          end

          it "copes with a global censor rule that affects the signature text" do
            opts = { text: 'Yours faithfully,',
                   replacement: 'Cheers!',
                   last_edit_editor: 'unknown',
                   last_edit_comment: 'none' }
            CensorRule.create!(opts)
            outgoing_message.apply_masks(outgoing_message.body, 'text/plain')

            outgoing_message.valid?
            expect(outgoing_message.errors.messages[:body]).
              to include("Please sign at the bottom with your name, or alter " \
                     "the \"Yours faithfully,\" signature")
          end

        end

      end

      context "when it's an internal review" do

        it "adds an error message if the text has not been changed" do
          outgoing_message =
            OutgoingMessage.new(status: 'ready',
                                message_type: 'followup',
                                what_doing: 'internal_review',
                                info_request: info_request)

          outgoing_message.valid?
          expect(outgoing_message.errors.messages[:body]).
            to include("Please give details explaining why you want a review")
        end

        it 'includes a all correspondence being available online' do
          outgoing_message =
            OutgoingMessage.new(status: 'ready',
                                message_type: 'followup',
                                what_doing: 'internal_review',
                                info_request: info_request)

          expect(outgoing_message.body).
            to include("A full history of my FOI request and all " \
                       "correspondence is available on the Internet at this " \
                       "address")
        end

        it 'removes the all correspondence line if the message is embargoed' do
          FactoryBot.create(:embargo, info_request: info_request)
          info_request.reload
          outgoing_message =
            OutgoingMessage.new(status: 'ready',
                                message_type: 'followup',
                                what_doing: 'internal_review',
                                info_request: info_request)

          expect(outgoing_message.body).
            not_to include("A full history of my FOI request and all " \
                          "correspondence is available on the Internet at " \
                          "this address")
        end

      end

      context "when it's an followup" do

        it "adds an error message if the text has not been changed" do
          outgoing_message =
            OutgoingMessage.new(status: 'ready',
                                message_type: 'followup',
                                what_doing: 'normal_sort',
                                info_request: info_request)

          outgoing_message.valid?
          expect(outgoing_message.errors.messages[:body]).
            to include("Please enter your follow up message")
        end

      end

    end

  end

  describe '#apply_masks' do

    before(:each) do
      @message = FactoryBot.create(:initial_request)

      @default_opts = { last_edit_editor: 'unknown',
                        last_edit_comment: 'none' }

    end

    it 'replaces text with global censor rules' do
      data = 'There was a mouse called Stilton, he wished that he was blue'
      expected = 'There was a mouse called Stilton, he said that he was blue'

      opts = { text: 'wished',
               replacement: 'said' }.merge(@default_opts)
      CensorRule.create!(opts)

      result = @message.apply_masks(data, 'text/plain')

      expect(result).to eq(expected)
    end

    it 'replaces text with censor rules belonging to the info request' do
      data = 'There was a mouse called Stilton.'
      expected = 'There was a cat called Jarlsberg.'

      rules = [
        { text: 'Stilton', replacement: 'Jarlsberg' },
        { text: 'm[a-z][a-z][a-z]e', regexp: true, replacement: 'cat' }
      ]

      rules.each do |rule|
        @message.info_request.censor_rules << CensorRule.new(rule.merge(@default_opts))
      end

      result = @message.apply_masks(data, 'text/plain')
      expect(result).to eq(expected)
    end

    it 'replaces text with censor rules belonging to the user' do
      data = 'There was a mouse called Stilton.'
      expected = 'There was a cat called Jarlsberg.'

      rules = [
        { text: 'Stilton', replacement: 'Jarlsberg' },
        { text: 'm[a-z][a-z][a-z]e', regexp: true, replacement: 'cat' }
      ]

      rules.each do |rule|
        @message.info_request.user.censor_rules << CensorRule.new(rule.merge(@default_opts))
      end

      result = @message.apply_masks(data, 'text/plain')
      expect(result).to eq(expected)
    end

    it 'replaces text with masks belonging to the info request' do
      data = "He emailed #{ @message.info_request.incoming_email }"
      expected = "He emailed [FOI ##{ @message.info_request.id } email]"
      result = @message.apply_masks(data, 'text/plain')
      expect(result).to eq(expected)
    end

    it 'replaces text with global masks' do
      data = 'His email address was stilton@example.org'
      expected = 'His email address was [email address]'
      result = @message.apply_masks(data, 'text/plain')
      expect(result).to eq(expected)
    end

    it 'replaces text in binary files' do
      data = 'His email address was stilton@example.org'
      expected = 'His email address was xxxxxxx@xxxxxxx.xxx'
      result = @message.apply_masks(data, 'application/vnd.ms-word')
      expect(result).to eq(expected)
    end

  end

  describe '#get_default_message' do

    context 'an initial_request' do

      it 'produces the expected text for a batch request template' do
        public_body = FactoryBot.build(:public_body,
                                       name: 'a test public body')
        info_request = FactoryBot.build(:info_request,
                                        title: 'A test title',
                                        public_body: public_body)
        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'initial_request',
                              what_doing: 'normal_sort',
                              info_request: info_request)

        expected_text = "Dear a test public body,\n\n\n\nYours faithfully,\n\n"
        expect(outgoing_message.get_default_message).to eq(expected_text)
      end

    end

    context 'a followup' do

      it 'produces the expected text for a followup' do
        public_body = FactoryBot.build(:public_body,
                                       name: 'a test public body')
        info_request = FactoryBot.build(:info_request,
                                        title: 'A test title',
                                        public_body: public_body)
        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'followup',
                              what_doing: 'normal_sort',
                              info_request: info_request)

        expected_text = "Dear a test public body,\n\n\n\nYours faithfully,\n\n"
        expect(outgoing_message.get_default_message).to eq(expected_text)
      end

      it 'produces the expected text for an incoming message followup' do
        public_body = FactoryBot.build(:public_body,
                                       name: 'A test public body')
        info_request = FactoryBot.build(:info_request,
                                        title: 'A test title',
                                        public_body: public_body)
        incoming_message =
          mock_model(IncomingMessage, safe_from_name: 'helpdesk',
                                      valid_to_reply_to?: true)
        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'followup',
                              what_doing: 'normal_sort',
                              info_request: info_request,
                              incoming_message_followup: incoming_message)

        expected_text = "Dear helpdesk,\n\n\n\nYours sincerely,\n\n"
        expect(outgoing_message.get_default_message).to eq(expected_text)
      end

    end

    context 'an internal_review' do

      it 'produces the expected text for an internal review request' do
        public_body = FactoryBot.build(:public_body,
                                       name: 'a test public body')
        info_request = FactoryBot.build(:info_request,
                                        title: 'a test title',
                                        public_body: public_body)
        outgoing_message =
          OutgoingMessage.new(status: 'ready',
                              message_type: 'followup',
                              what_doing: 'internal_review',
                              info_request: info_request)

        expected_text = <<-EOF.strip_heredoc
        Dear a test public body,

        Please pass this on to the person who conducts Freedom of Information reviews.

        I am writing to request an internal review of a test public body's handling of my FOI request 'a test title'.



         [ GIVE DETAILS ABOUT YOUR COMPLAINT HERE ]



        A full history of my FOI request and all correspondence is available on the Internet at this address: http://test.host/request/a_test_title


        Yours faithfully,

        EOF

        expect(outgoing_message.get_default_message).to eq(expected_text)
      end

    end

  end

  describe '#get_body_for_html_display' do

    before do
      @outgoing_message = OutgoingMessage.new({
                                                status: 'ready',
                                                message_type: 'initial_request',
                                                body: 'This request contains a foo@bar.com email address',
                                                last_sent_at: Time.zone.now,
                                                what_doing: 'normal_sort'
      })
    end

    it "does not display email addresses on page" do
      expect(@outgoing_message.get_body_for_html_display).not_to include("foo@bar.com")
    end

    it "links to help page where email address was" do
      expect(@outgoing_message.get_body_for_html_display).to include('<a href="/help/officers#mobiles">')
    end

    it "does not force long lines to wrap" do
      long_line = "long string of 125 characters, set so the old line break " \
                  "falls here, and making sure even longer lines are not " \
                  "affected either"
      @outgoing_message.body = long_line
      expect(@outgoing_message.get_body_for_html_display).to eq("<p>#{long_line}</p>")
    end

    it "interprets single line breaks as <br> tags" do
      split_line = "Hello,\nI am a test message\nWith multiple lines"
      expected = "<p>Hello,\n<br />I am a test message\n<br />With multiple lines</p>"
      @outgoing_message.body = split_line
      expect(@outgoing_message.get_body_for_html_display).to include(expected)
    end

    it "interprets double line breaks as <p> tags" do
      split_line = "Hello,\n\nI am a test message\n\nWith multiple lines"
      expected = "<p>Hello,</p>\n\n<p>I am a test message</p>\n\n<p>With multiple lines</p>"
      @outgoing_message.body = split_line
      expect(@outgoing_message.get_body_for_html_display).to include(expected)
    end

    it "removes excess linebreaks" do
      split_line = "Line 1\n\n\n\n\n\n\n\n\n\nLine 2"
      expected = "<p>Line 1</p>\n\n<p>Line 2</p>"
      @outgoing_message.body = split_line
      expect(@outgoing_message.get_body_for_html_display).to include(expected)
    end

  end

  describe '#get_text_for_indexing' do
    subject { message.get_text_for_indexing(strip_salutation, opts) }

    # Default opts
    let(:strip_salutation) { true }
    let(:opts) { {} }

    let(:message) do
      public_body = FactoryBot.build(:public_body, name: 'Example Body')
      info_request = FactoryBot.build(:info_request, public_body: public_body)
      FactoryBot.build(:initial_request, info_request: info_request, body: body)
    end

    let(:body) { "Dear Example Body,\n\n\r\nSome information please." }

    context 'when stripping salutation' do
      let(:strip_salutation) { true }
      it { is_expected.not_to match(/Dear Example Body/) }
      it { is_expected.not_to start_with(/\s+/) }
    end

    context 'when stripping localised salutation' do
      let(:body) { "Estimado Example Body,\n\nAlguna información por favor." }

      around do |example|
        AlaveteliLocalization.with_locale(:es) do
          example.run
        end
      end

      it { is_expected.not_to match(/Estimado Example Body/) }
    end

    context 'when not stripping salutation' do
      let(:strip_salutation) { false }
      it { is_expected.to match(/Dear Example Body/) }
    end
  end

  describe '#is_owning_user?' do

    it 'returns true if the user is the owning user of the info request' do
      request = FactoryBot.build(:info_request)
      message = FactoryBot.build(:initial_request, info_request: request)
      expect(message.is_owning_user?(request.user)).to eq(true)
    end

    it 'returns false if the user is not the owning user of the info request' do
      user = FactoryBot.create(:user)
      request = FactoryBot.create(:info_request)
      message = FactoryBot.build(:initial_request, info_request: request)
      expect(message.is_owning_user?(user)).to eq(false)
    end

  end

  describe '#smtp_message_ids' do

    context 'a sent message' do

      it 'returns one smtp_message_id when a message has been sent once' do
        message = FactoryBot.create(:initial_request)
        smtp_id = message.info_request_events.first.params[:smtp_message_id]
        expect(message.smtp_message_ids).to eq([smtp_id])
      end

      it 'removes the enclosing angle brackets' do
        message = FactoryBot.create(:initial_request)
        smtp_id = message.info_request_events.first.params[:smtp_message_id]
        old_format_smtp_id = "<#{ smtp_id }>"
        message.
          info_request_events.
            first.
              update(params: { smtp_message_id: old_format_smtp_id })
        expect(message.smtp_message_ids).to eq([smtp_id])
      end

      it 'returns an empty array if the smtp_message_id was not logged' do
        message = FactoryBot.create(:initial_request)
        message.info_request_events.first.update(params: {})
        expect(message.smtp_message_ids).to be_empty
      end

    end

    context 'a resent message' do

      it 'returns an smtp_message_id each time the message has been sent' do
        message = FactoryBot.create(:initial_request)
        smtp_id_1 = message.info_request_events.first.params[:smtp_message_id]

        message.prepare_message_for_resend

        mail_message = OutgoingMailer.initial_request(
          message.info_request,
          message
        ).deliver_now

        message.record_email_delivery(
          mail_message.to_addrs.join(', '),
          mail_message.message_id,
          'resent'
        )

        smtp_id_2 = mail_message.message_id

        message.prepare_message_for_resend

        mail_message = OutgoingMailer.initial_request(
          message.info_request,
          message
        ).deliver_now

        message.record_email_delivery(
          mail_message.to_addrs.join(', '),
          mail_message.message_id,
          'resent'
        )

        smtp_id_3 = mail_message.message_id

        expect(message.smtp_message_ids).
          to eq([smtp_id_1, smtp_id_2, smtp_id_3])
      end

      it 'returns known smtp_message_ids if some were not logged' do
        message = FactoryBot.create(:initial_request)
        smtp_id_1 = message.info_request_events.first.params[:smtp_message_id]

        message.prepare_message_for_resend

        mail_message = OutgoingMailer.initial_request(
          message.info_request,
          message
        ).deliver_now

        message.record_email_delivery(
          mail_message.to_addrs.join(', '),
          nil,
          'resent'
        )

        smtp_id_2 = mail_message.message_id

        message.prepare_message_for_resend

        mail_message = OutgoingMailer.initial_request(
          message.info_request,
          message
        ).deliver_now

        message.record_email_delivery(
          mail_message.to_addrs.join(', '),
          mail_message.message_id,
          'resent'
        )

        smtp_id_3 = mail_message.message_id

        expect(message.smtp_message_ids).
          to eq([smtp_id_1, smtp_id_3])
      end

    end

  end

  describe '#mta_ids' do

    context 'when exim is the MTA' do

      before do
        allow(AlaveteliConfiguration).to receive(:mta_log_type).and_return("exim")
      end

      context 'a sent message' do

        it 'returns one mta_id when a message has been sent once' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17814] 1ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          expect(message.mta_ids).to eq(['1ZsFHb-0004dK-SM'])
        end

        it 'returns one mta_id when a message has syslog format logs' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          Oct  30 19:24:16 host exim[7706]: 2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          Oct  30 19:24:16 host exim[7706]: 2015-10-30 19:24:16 [17814] 1ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }2015-10-30 19:24:16 [17814] 1ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          Oct  30 19:24:15 host exim[7706]: 2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          expect(message.mta_ids).to eq(['1ZsFHb-0004dK-SM'])
        end

        it 'returns an empty array if the mta_id could not be found' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = 'unknown@localhost'
          request_subject = 'Unknown'
          smtp_message_id = 'ogm-11+1111111111111-1111@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17814] 1ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          expect(message.mta_ids).to be_empty
        end

      end

      context 'a resent message' do

        it 'returns an mta_id each time the message has been sent' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17814] 1ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          message.prepare_message_for_resend

          mail_message = OutgoingMailer.initial_request(
            message.info_request,
            message
          ).deliver_now

          message.record_email_delivery(
            mail_message.to_addrs.join(', '),
            mail_message.message_id,
            'resent'
          )

          smtp_message_id = mail_message.message_id

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-10-30 19:24:16 [17817] 2ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17814] 2ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          message.prepare_message_for_resend

          mail_message = OutgoingMailer.initial_request(
            message.info_request,
            message
          ).deliver_now

          message.record_email_delivery(
            mail_message.to_addrs.join(', '),
            mail_message.message_id,
            'resent'
          )

          request_email = 'unknown@localhost'
          request_subject = 'Unknown'
          smtp_message_id = 'ogm-11+1111111111111-1111@localhost'
          smtp_message_id = mail_message.message_id

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-10-30 19:24:16 [17817] 3ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17814] 3ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          expect(message.mta_ids).
            to eq(%w(1ZsFHb-0004dK-SM 2ZsFHb-0004dK-SM))
        end

        it 'returns the known mta_ids if some outgoing messages were not logged' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17814] 1ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          # Resend the message without importing exim logs for it, simulating a
          # lost log file or similar.
          message.prepare_message_for_resend

          mail_message = OutgoingMailer.initial_request(
            message.info_request,
            message
          ).deliver_now

          message.record_email_delivery(
            mail_message.to_addrs.join(', '),
            mail_message.message_id,
            'resent'
          )

          message.prepare_message_for_resend

          mail_message = OutgoingMailer.initial_request(
            message.info_request,
            message
          ).deliver_now

          message.record_email_delivery(
            mail_message.to_addrs.join(', '),
            mail_message.message_id,
            'resent'
          )

          smtp_message_id = mail_message.message_id

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-10-30 19:24:16 [17817] 3ZsFHb-0004dK-SM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17814] 3ZsFHb-0004dK-SM <= #{ request_email } U=alaveteli P=local S=2252 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-30 19:24:15 [17814] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          EOF

          expect(message.mta_ids).
            to eq(%w(1ZsFHb-0004dK-SM 3ZsFHb-0004dK-SM))
        end
      end

      context 'when Postfix is the MTA' do

        before do
          allow(AlaveteliConfiguration).to receive(:mta_log_type).and_return("postfix")
        end

        context 'a sent message' do

          it 'returns one mta_id when a message has been sent once' do
            message = FactoryBot.create(:initial_request)
            body_email = message.info_request.public_body.request_email
            request_email = message.info_request.incoming_email
            request_subject = message.info_request.email_subject_request(html: false)
            smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

            load_mail_server_logs <<-EOF.strip_heredoc
            Jun 15 16:02:40 host postfix/qmgr[5216]: BA6A236F4E08: removed
            Jun 15 16:02:40 host postfix/smtp[12120]: BA6A236F4E08: to=<#{ body_email }>, relay=example.com[0.0.0.0]:25, delay=1.2, delays=0.12/0.01/0.96/0.09, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as B7F313A054)
            Jun 15 16:02:39 host postfix/qmgr[5216]: BA6A236F4E08: from=<#{ request_email }>, size=1499, nrcpt=1 (queue active)
            Jun 15 16:02:39 host postfix/cleanup[12118]: BA6A236F4E08: message-id=<#{ smtp_message_id }>
            Jun 15 16:02:39 host postfix/pickup[31710]: BA6A236F4E08: uid=1003 from=<#{ request_email }>
            EOF

            expect(message.mta_ids).to eq(['BA6A236F4E08'])
          end

          it 'returns an empty array if the mta_id could not be found' do
            message = FactoryBot.create(:initial_request)
            body_email = message.info_request.public_body.request_email
            request_email = 'unknown@localhost'
            request_subject = 'Unknown'
            smtp_message_id = 'ogm-11+1111111111111-1111@localhost'

            load_mail_server_logs <<-EOF.strip_heredoc
            Jun 15 16:02:40 host postfix/qmgr[5216]: BA6A236F4E08: removed
            Jun 15 16:02:40 host postfix/smtp[12120]: BA6A236F4E08: to=<#{ body_email }>, relay=example.com[0.0.0.0]:25, delay=1.2, delays=0.12/0.01/0.96/0.09, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as B7F313A054)
            Jun 15 16:02:39 host postfix/qmgr[5216]: BA6A236F4E08: from=<#{ request_email }>, size=1499, nrcpt=1 (queue active)
            Jun 15 16:02:39 host postfix/cleanup[12118]: BA6A236F4E08: message-id=<#{ smtp_message_id }>
            Jun 15 16:02:39 host postfix/pickup[31710]: BA6A236F4E08: uid=1003 from=<#{ request_email }>
            EOF

            expect(message.mta_ids).to be_empty
          end

        end

        context 'a resent message' do

          it 'returns an mta_id each time the message has been sent' do
            message = FactoryBot.create(:initial_request)
            body_email = message.info_request.public_body.request_email
            request_email = message.info_request.incoming_email
            request_subject = message.info_request.email_subject_request(html: false)
            smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

            load_mail_server_logs <<-EOF.strip_heredoc
            Jun 15 16:02:40 host postfix/qmgr[5216]: 1A6A236F4E08: removed
            Jun 15 16:02:40 host postfix/smtp[12120]: 1A6A236F4E08: to=<#{ body_email }>, relay=example.com[0.0.0.0]:25, delay=1.2, delays=0.12/0.01/0.96/0.09, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as B7F313A054)
            Jun 15 16:02:39 host postfix/qmgr[5216]: 1A6A236F4E08: from=<#{ request_email }>, size=1499, nrcpt=1 (queue active)
            Jun 15 16:02:39 host postfix/cleanup[12118]: 1A6A236F4E08: message-id=<#{ smtp_message_id }>
            Jun 15 16:02:39 host postfix/pickup[31710]: 1A6A236F4E08: uid=1003 from=<#{ request_email }>
            EOF

            message.prepare_message_for_resend

            mail_message = OutgoingMailer.initial_request(
              message.info_request,
              message
            ).deliver_now

            message.record_email_delivery(
              mail_message.to_addrs.join(', '),
              mail_message.message_id,
              'resent'
            )

            smtp_message_id = mail_message.message_id

            load_mail_server_logs <<-EOF.strip_heredoc
            Jun 15 16:02:40 host postfix/qmgr[5216]: 2A6A236F4E08: removed
            Jun 15 16:02:40 host postfix/smtp[12120]: 2A6A236F4E08: to=<#{ body_email }>, relay=example.com[0.0.0.0]:25, delay=1.2, delays=0.12/0.01/0.96/0.09, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as B7F313A054)
            Jun 15 16:02:39 host postfix/qmgr[5216]: 2A6A236F4E08: from=<#{ request_email }>, size=1499, nrcpt=1 (queue active)
            Jun 15 16:02:39 host postfix/cleanup[12118]: 2A6A236F4E08: message-id=<#{ smtp_message_id }>
            Jun 15 16:02:39 host postfix/pickup[31710]: 2A6A236F4E08: uid=1003 from=<#{ request_email }>
            EOF

            message.prepare_message_for_resend

            mail_message = OutgoingMailer.initial_request(
              message.info_request,
              message
            ).deliver_now

            message.record_email_delivery(
              mail_message.to_addrs.join(', '),
              mail_message.message_id,
              'resent'
            )

            request_email = 'unknown@localhost'
            request_subject = 'Unknown'
            smtp_message_id = 'ogm-11+1111111111111-1111@localhost'
            smtp_message_id = mail_message.message_id

            load_mail_server_logs <<-EOF.strip_heredoc
            Jun 15 16:02:40 host postfix/qmgr[5216]: 3A6A236F4E08: removed
            Jun 15 16:02:40 host postfix/smtp[12120]: 3A6A236F4E08: to=<#{ body_email }>, relay=example.com[0.0.0.0]:25, delay=1.2, delays=0.12/0.01/0.96/0.09, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as B7F313A054)
            Jun 15 16:02:39 host postfix/qmgr[5216]: 3A6A236F4E08: from=<#{ request_email }>, size=1499, nrcpt=1 (queue active)
            Jun 15 16:02:39 host postfix/cleanup[12118]: 3A6A236F4E08: message-id=<#{ smtp_message_id }>
            Jun 15 16:02:39 host postfix/pickup[31710]: 3A6A236F4E08: uid=1003 from=<#{ request_email }>
            EOF

            expect(message.mta_ids).
              to eq(%w(1A6A236F4E08 2A6A236F4E08))
          end

          it 'returns the known mta_ids if some outgoing messages were not logged' do
            message = FactoryBot.create(:initial_request)
            body_email = message.info_request.public_body.request_email
            request_email = message.info_request.incoming_email
            request_subject = message.info_request.email_subject_request(html: false)
            smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

            load_mail_server_logs <<-EOF.strip_heredoc
            Jun 15 16:02:40 host postfix/qmgr[5216]: 1A6A236F4E08: removed
            Jun 15 16:02:40 host postfix/smtp[12120]: 1A6A236F4E08: to=<#{ body_email }>, relay=example.com[0.0.0.0]:25, delay=1.2, delays=0.12/0.01/0.96/0.09, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as B7F313A054)
            Jun 15 16:02:39 host postfix/qmgr[5216]: 1A6A236F4E08: from=<#{ request_email }>, size=1499, nrcpt=1 (queue active)
            Jun 15 16:02:39 host postfix/cleanup[12118]: 1A6A236F4E08: message-id=<#{ smtp_message_id }>
            Jun 15 16:02:39 host postfix/pickup[31710]: 1A6A236F4E08: uid=1003 from=<#{ request_email }>
            EOF

            # Resend the message without importing postfix logs for it, simulating a
            # lost log file or similar.
            message.prepare_message_for_resend

            mail_message = OutgoingMailer.initial_request(
              message.info_request,
              message
            ).deliver_now

            message.record_email_delivery(
              mail_message.to_addrs.join(', '),
              mail_message.message_id,
              'resent'
            )

            message.prepare_message_for_resend

            mail_message = OutgoingMailer.initial_request(
              message.info_request,
              message
            ).deliver_now

            message.record_email_delivery(
              mail_message.to_addrs.join(', '),
              mail_message.message_id,
              'resent'
            )

            smtp_message_id = mail_message.message_id

            load_mail_server_logs <<-EOF.strip_heredoc
            Jun 15 16:02:40 host postfix/qmgr[5216]: 3A6A236F4E08: removed
            Jun 15 16:02:40 host postfix/smtp[12120]: 3A6A236F4E08: to=<#{ body_email }>, relay=example.com[0.0.0.0]:25, delay=1.2, delays=0.12/0.01/0.96/0.09, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as B7F313A054)
            Jun 15 16:02:39 host postfix/qmgr[5216]: 3A6A236F4E08: from=<#{ request_email }>, size=1499, nrcpt=1 (queue active)
            Jun 15 16:02:39 host postfix/cleanup[12118]: 3A6A236F4E08: message-id=<#{ smtp_message_id }>
            Jun 15 16:02:39 host postfix/pickup[31710]: 3A6A236F4E08: uid=1003 from=<#{ request_email }>
            EOF

            expect(message.mta_ids).
              to eq(%w(1A6A236F4E08 3A6A236F4E08))
          end
        end

      end

    end

    describe '#mail_server_logs' do

      context 'when exim is the MTA' do

        before do
          allow(AlaveteliConfiguration).
            to receive(:mta_log_type).and_return('exim')
        end

        it 'finds the mail server logs associated with a sent message' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          2016-02-03 06:58:10 [16003] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f request-313973-1650c56a@localhost --
          foi@body.example.com
          2016-02-03 06:58:11 [16003] 1aQrOE-0004A7-TL <= request-313973-1650c56a@localhost U=alaveteli P=local S=3098 id=ogm-512169+56b3a50ac0cf4-6717@localhost T="Freedom of Information request - Rspec" from <request-313973-1650c56a@localhost> for foi@body.example.com foi@body.example.com
          2016-02-03 06:58:11 [16006] cwd=/var/spool/exim4 3 args: /usr/sbin/exim4 -Mc 1aQrOE-0004A7-TL
          2016-02-03 06:58:12 [16006] 1aQrOE-0004A7-TL => foi@body.example.com F=<request-313973-1650c56a@localhost> P=<request-313973-1650c56a@localhost> R=dnslookup T=remote_smtp S=3170 H=authority.mail.protection.example.com [213.199.154.87]:25 X=TLS1.2:RSA_AES_256_CBC_SHA256:256 CV=no DN="C=US,ST=WA,L=Redmond,O=Microsoft,OU=Forefront Online Protection for Exchange,CN=mail.protection.outlook.com" C="250 2.6.0 <ogm-512169+56b3a50ac0cf4-6717@localhost> [InternalId=41399189774878, Hostname=HE" QT=2s DT=1s
          2016-02-03 06:58:12 [16006] 1aQrOE-0004A7-TL Completed QT=2s
          2016-02-03 06:58:55 [31388] SMTP connection from [127.0.0.1]:41019 I=[127.0.0.1]:25 (TCP/IP connection count = 1)
          2016-02-03 06:58:56 [16211] 1aQrOx-0004DT-PC <= medications-cheapest5@broadband.hu H=nil.ukcod.org.uk [127.0.0.1]:41019 I=[127.0.0.1]:25 P=esmtp S=31163 T="Spam" from <medications-cheapest5@broadband.hu> for foi@unknown.ukcod.org.uk
          2016-02-03 06:58:56 [16212] cwd=/var/spool/exim4 3 args: /usr/sbin/exim4 -Mc 1aQrOx-0004DT-PC
          2016-02-03 06:58:56 [16211] SMTP connection from nil.ukcod.org.uk [127.0.0.1]:41019 I=[127.0.0.1]:25 closed by QUIT
          2016-02-03 06:58:56 [16287] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ smtp_message_id } -- #{ body_email }
          2016-02-03 06:58:56 [16287] 1aQrOy-0004Eh-H7 <= #{ request_email } U=alaveteli P=local S=2329 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2016-02-03 06:58:56 [16291] cwd=/var/spool/exim4 3 args: /usr/sbin/exim4 -Mc 1aQrOy-0004Eh-H7
          2016-02-03 06:58:57 [16291] 1aQrOy-0004Eh-H7 => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2394 H=cluster1.uk.example.com [85.158.143.3]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail14.messagelabs.com" C="250 ok 1454482737 qp 41621 server-16.tower-14.example.com!1454482736!6386345!1" QT=1s DT=1s
          2016-02-03 06:58:57 [16291] 1aQrOy-0004Eh-H7 Completed QT=1s
          2016-02-03 06:59:17 [16212] 1aQrOx-0004DT-PC => |/home/alaveteli/run-with-rbenv-path /var/www/alaveteli/alaveteli/script/mailin <foi@unknown.ukcod.org.uk> F=<medications-cheapest5@broadband.hu> P=<medications-cheapest5@broadband.hu> R=userforward_unsuffixed T=address_pipe S=31362 QT=22s DT=21s
          2016-02-03 06:59:17 [16212] 1aQrOx-0004DT-PC Completed QT=22s
          2016-02-03 06:59:49 [31388] SMTP connection from [46.235.226.171]:57365 I=[127.0.0.1]:25 (TCP/IP connection count = 1)
          2016-02-03 06:59:49 [16392] SMTP connection from null.ukcod.org.uk (null) [46.235.226.171]:57365 I=[127.0.0.1]:25 closed by QUIT
          2016-02-03 06:59:49 [16392] no MAIL in SMTP connection from null.ukcod.org.uk (null) [46.235.226.171]:57365 I=[127.0.0.1]:25 D=0s C=HELO,QUIT
          EOF

          expected_lines = <<-EOF.strip_heredoc
          2016-02-03 06:58:56 [16287] 1aQrOy-0004Eh-H7 <= #{ request_email } U=alaveteli P=local S=2329 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2016-02-03 06:58:57 [16291] 1aQrOy-0004Eh-H7 => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2394 H=cluster1.uk.example.com [85.158.143.3]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail14.messagelabs.com" C="250 ok 1454482737 qp 41621 server-16.tower-14.example.com!1454482736!6386345!1" QT=1s DT=1s
          EOF

          expect(message.mail_server_logs.map(&:line)).
            to eq(expected_lines.scan(/[^\n]*\n/))
        end

        it 'finds the mail server logs associated with a resent message' do
          message = FactoryBot.create(:internal_review_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          message.prepare_message_for_resend

          mail_message = OutgoingMailer.initial_request(
            message.info_request,
            message
          ).deliver_now

          message.record_email_delivery(
            mail_message.to_addrs.join(', '),
            mail_message.message_id,
            'resent'
          )

          resent_smtp_message_id = mail_message.message_id

          load_mail_server_logs <<-EOF.strip_heredoc
          2015-09-22 17:36:56 [2035] 1ZeQYq-0000Wm-1V => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=1685 H=mail.example.com [62.208.144.158]:25 C="250 2.0.0 Ok: queued as 95FC94583B8" QT=0s DT=0s
          2015-09-22 17:36:56 [2032] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          2015-09-22 17:36:56 [2032] 1ZeQYq-0000Wm-1V <= #{ request_email } U=alaveteli P=local S=1645 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-21 10:28:01 [10354] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          2015-10-21 10:28:01 [10354] 1Zopgf-0002h0-3S <= #{ request_email } U=alaveteli P=local S=1323 id=ogm-+56275aa1046c0-d660@localhost T="Re: #{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-10-21 10:28:01 [10420] 1Zopgf-0002h0-3S => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=1359 H=mail.example.com [62.208.144.158]:25 C="250 2.0.0 Ok: queued as A84A244B926" QT=0s DT=0s
          2015-11-06 10:49:25 [23969] 1ZueaD-0006Eb-Cx <= #{ request_email } U=alaveteli P=local S=1901 id=ogm-+563c85b54d2ed-73c6@localhost T="Internal review of #{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-11-06 10:49:26 [24015] 1ZueaD-0006Eb-Cx => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=1945 H=mail.example.com [62.208.144.158]:25 C="250 2.0.0 Ok: queued as 35671838115" QT=1s DT=1s
          2015-11-06 10:49:25 [23969] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          2015-11-16 20:55:54 [31964] 1ZyQoc-0008JY-DM <= #{ request_email } U=alaveteli P=local S=1910 id=ogm-+564a42da4ea11-8a2e@localhost T="Internal review of #{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-11-16 20:55:55 [31967] 1ZyQoc-0008JY-DM => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=1953 H=mail.example.com [62.208.144.158]:25 C="250 2.0.0 Ok: queued as 03958448DA3" QT=1s DT=1s
          2015-11-16 20:55:54 [31964] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          2015-11-17 05:50:22 [32285] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          2015-11-17 05:50:22 [32285] 1ZyZ9q-0008Oj-JH <= #{ request_email } U=alaveteli P=local S=3413 id=ogm-+564ac01e5ab3c-98e6@localhost T="RE: #{ request_subject } 15" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-11-17 05:50:24 [32288] 1ZyZ9q-0008Oj-JH => #{ body_email } <#{ body_email }> F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=3559 H=prefilter.emailsecurity.trendmicro.eu [150.70.226.147]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Cupertino,O=Trend Micro Inc.,CN=*.emailsecurity.trendmicro.eu" C="250 2.0.0 Ok: queued as 318214E002E" QT=2s DT=2s
          2015-11-22 00:37:01 [17622] 1a0IeK-0004aB-Na => #{ body_email } <#{ body_email }> F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=4137 H=prefilter.emailsecurity.trendmicro.eu [150.70.226.147]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Cupertino,O=Trend Micro Inc.,CN=*.emailsecurity.trendmicro.eu" C="250 2.0.0 Ok: queued as 8878A680030" QT=1s DT=0s
          2015-11-22 00:37:00 [17619] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          2015-11-22 00:37:00 [17619] 1a0IeK-0004aB-Na <= #{ request_email } U=alaveteli P=local S=3973 id=#{ resent_smtp_message_id }@localhost T="RE: #{ request_subject } 15" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-12-01 17:05:37 [26935] 1a3oMy-00070R-SQ <= #{ request_email } U=alaveteli P=local S=2016 id=ogm-+565dd360be2ca-2767@localhost T="Re: #{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-12-01 17:05:36 [26935] cwd=/var/www/alaveteli/alaveteli 7 args: /usr/sbin/sendmail -i -t -f #{ request_email } -- #{ body_email }
          2015-12-01 17:05:38 [26938] 1a3oMy-00070R-SQ => #{ body_email } <#{ body_email }> F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=2071 H=prefilter.emailsecurity.trendmicro.eu [150.70.226.147]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Cupertino,O=Trend Micro Inc.,CN=*.emailsecurity.trendmicro.eu" C="250 2.0.0 Ok: queued as D177C4C002F" QT=2s DT=0s
          EOF

          expected_lines = <<-EOF.strip_heredoc
          2015-09-22 17:36:56 [2035] 1ZeQYq-0000Wm-1V => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=1685 H=mail.example.com [62.208.144.158]:25 C="250 2.0.0 Ok: queued as 95FC94583B8" QT=0s DT=0s
          2015-09-22 17:36:56 [2032] 1ZeQYq-0000Wm-1V <= #{ request_email } U=alaveteli P=local S=1645 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2015-11-22 00:37:01 [17622] 1a0IeK-0004aB-Na => #{ body_email } <#{ body_email }> F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=4137 H=prefilter.emailsecurity.trendmicro.eu [150.70.226.147]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Cupertino,O=Trend Micro Inc.,CN=*.emailsecurity.trendmicro.eu" C="250 2.0.0 Ok: queued as 8878A680030" QT=1s DT=0s
          2015-11-22 00:37:00 [17619] 1a0IeK-0004aB-Na <= #{ request_email } U=alaveteli P=local S=3973 id=#{ resent_smtp_message_id }@localhost T="RE: #{ request_subject } 15" from <#{ request_email }> for #{ body_email } #{ body_email }
          EOF

          expect(message.mail_server_logs.map(&:line)).
            to eq(expected_lines.scan(/[^\n]*\n/))
        end

        it 'finds logs passed through an indirect router' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          2017-01-01 16:26:56 [6537] 1cNiyG-0001hR-8R <= #{ request_email } U=alaveteli P=local S=2489 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2017-01-01 16:26:56 [6540] cwd=/var/spool/exim4 3 args: /usr/sbin/exim4 -Mc 1cNiyG-0001hR-8R
          2017-01-01 16:26:57 [6540] 1cNiyG-0001hR-8R => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=send_to_smarthost T=remote_smtp S=2555 H=mail.example.com [62.208.144.158]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="CN=mx0.mysociety.org" C="250 OK id=1cNiyG-00040U-Ls" QT=1s DT=1s
          2017-01-01 16:26:57 [6540] 1cNiyG-0001hR-8R Completed QT=1s
          2017-01-01 16:26:57 [15406] 1cNiyG-00040U-Ls <= #{ request_email } H=mail.example.com [127.0.0.1]:57486 I=[127.0.0.1]:25 P=esmtps X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no S=2773 id=ogm-609600+58692dd023de0-dcdd@whatdotheyknow.com T="#{ request_subject }" from <#{ request_email }> for #{ body_email }
          2017-01-01 16:26:57 [15407] cwd=/disk1/spool/exim4 3 args: /usr/sbin/exim4 -Mc 1cNiyG-00040U-Ls
          2017-01-01 16:26:57 [15407] 1cNiyG-00040U-Ls => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup_returnpath_dkim T=remote_smtp_dkim_returnpath S=2845 H=prefilter.emailsecurity.trendmicro.eu [150.70.226.147]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Cupertino,O=Trend Micro Inc.,CN=*.emailsecurity.trendmicro.eu" C="250 2.0.0 Ok: queued as 8630B4C0035" QT=1s DT=0s
          2017-01-01 16:26:57 [15407] 1cNiyG-00040U-Ls Completed QT=1s
          EOF

          expected_lines = <<-EOF.strip_heredoc
          2017-01-01 16:26:56 [6537] 1cNiyG-0001hR-8R <= #{ request_email } U=alaveteli P=local S=2489 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2017-01-01 16:26:57 [6540] 1cNiyG-0001hR-8R => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=send_to_smarthost T=remote_smtp S=2555 H=mail.example.com [62.208.144.158]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="CN=mx0.mysociety.org" C="250 OK id=1cNiyG-00040U-Ls" QT=1s DT=1s
          2017-01-01 16:26:57 [15406] 1cNiyG-00040U-Ls <= #{ request_email } H=mail.example.com [127.0.0.1]:57486 I=[127.0.0.1]:25 P=esmtps X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no S=2773 id=ogm-609600+58692dd023de0-dcdd@whatdotheyknow.com T="#{ request_subject }" from <#{ request_email }> for #{ body_email }
          2017-01-01 16:26:57 [15407] 1cNiyG-00040U-Ls => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup_returnpath_dkim T=remote_smtp_dkim_returnpath S=2845 H=prefilter.emailsecurity.trendmicro.eu [150.70.226.147]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Cupertino,O=Trend Micro Inc.,CN=*.emailsecurity.trendmicro.eu" C="250 2.0.0 Ok: queued as 8630B4C0035" QT=1s DT=0s
          EOF

          expect(message.mail_server_logs.map(&:line)).
            to eq(expected_lines.scan(/[^\n]*\n/))
        end


        it 'handles log lines where a delivery status cant be parsed' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          2014-03-25 15:35:42 [3719] 1WSTOA-0000xz-JF <= #{ request_email } U=alaveteli P=local S=2949 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2014-03-25 15:35:50 [3723] 1WSTOA-0000xz-JF SMTP error from remote mail server after RCPT TO:<#{ body_email }>: host mx.canterbury.ac.uk [127.0.0.1]: 451-127.0.0.2 is not yet authorized to deliver mail from\\n451-<#{ request_email }> to <#{ body_email }>.\\n451 Please try later.
          2014-03-25 15:35:55 [3721] 1WSTOA-0000xz-JF == #{ body_email } R=dnslookup T=remote_smtp defer (-44): SMTP error from remote mail server after RCPT TO:<#{ body_email }>: host mx.core.canterbury.ac.uk [127.0.0.1]: 451-127.0.0.2 is not yet authorized to deliver mail from\\n451-<#{ request_email }> to <#{ body_email }>.\\n451 Please try later.
          2014-03-25 15:51:01 [7248] 1WSTOA-0000xz-JF => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=3003 H=mx.core.canterbury.ac.uk [127.0.0.1]:25 X=TLS1.0:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=GB,postalCode=CT1 1QU,ST=Kent,L=CANTERBURY,STREET=North Holmes Road,O=Canterbury Christ Church University,OU=Computing Services,CN=mx.core.canterbury.ac.uk" C="250 OK id=1WSTcz-0002ft-2W" QT=15m19s DT=1s
          EOF

          expected_lines = <<-EOF.strip_heredoc
          2014-03-25 15:35:42 [3719] 1WSTOA-0000xz-JF <= #{ request_email } U=alaveteli P=local S=2949 id=#{ smtp_message_id } T="#{ request_subject }" from <#{ request_email }> for #{ body_email } #{ body_email }
          2014-03-25 15:35:50 [3723] 1WSTOA-0000xz-JF SMTP error from remote mail server after RCPT TO:<#{ body_email }>: host mx.canterbury.ac.uk [127.0.0.1]: 451-127.0.0.2 is not yet authorized to deliver mail from\\n451-<#{ request_email }> to <#{ body_email }>.\\n451 Please try later.
          2014-03-25 15:35:55 [3721] 1WSTOA-0000xz-JF == #{ body_email } R=dnslookup T=remote_smtp defer (-44): SMTP error from remote mail server after RCPT TO:<#{ body_email }>: host mx.core.canterbury.ac.uk [127.0.0.1]: 451-127.0.0.2 is not yet authorized to deliver mail from\\n451-<#{ request_email }> to <#{ body_email }>.\\n451 Please try later.
          2014-03-25 15:51:01 [7248] 1WSTOA-0000xz-JF => #{ body_email } F=<#{ request_email }> P=<#{ request_email }> R=dnslookup T=remote_smtp S=3003 H=mx.core.canterbury.ac.uk [127.0.0.1]:25 X=TLS1.0:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=GB,postalCode=CT1 1QU,ST=Kent,L=CANTERBURY,STREET=North Holmes Road,O=Canterbury Christ Church University,OU=Computing Services,CN=mx.core.canterbury.ac.uk" C="250 OK id=1WSTcz-0002ft-2W" QT=15m19s DT=1s
          EOF

          expect(message.mail_server_logs.map(&:line)).
            to eq(expected_lines.scan(/[^\n]*\n/))
        end

      end

      context 'when postfix is the MTA' do

        before do
          allow(AlaveteliConfiguration).
            to receive(:mta_log_type).and_return('postfix')
        end

        it 'finds the mail server logs associated with a sent message' do
          message = FactoryBot.create(:initial_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          load_mail_server_logs <<-EOF.strip_heredoc
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: removed
          Jun 15 20:59:18 host postfix/pickup[17736]: 053EF36F5B67: uid=1003 from=<#{ request_email }>
          Jun 15 20:59:18 host postfix/cleanup[4358]: 053EF36F5B67: message-id=<#{ smtp_message_id }>
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: from=<#{ request_email }>, size=2070, nrcpt=1 (queue active)
          Jun 15 20:59:18 host postfix/smtp[3848]: 053EF36F5B67: to=<#{ body_email }>, relay=relay.example.com[165.12.251.85]:25, delay=0.98, delays=0.08/0/0.5/0.4, dsn=2.0.0, status=sent (250 ok:  Message 114541484 accepted)
          Jun 16 10:34:56 host postfix/qmgr[5216]: A442636F4E08: removed
          Jun 16 10:34:56 host postfix/pipe[26650]: A442636F4E08: to=<alaveteli@localhostlocalhost>, orig_to=<#{ request_email }>, relay=alaveteli, delay=18, delays=0.62/0.01/0/17, dsn=2.0.0, status=sent (delivered via alaveteli service)
          Jun 16 10:34:39 host postfix/qmgr[5216]: A442636F4E08: from=<prvs=968dc94c7=HIGHERED@localhost>, size=19457, nrcpt=1 (queue active)
          Jun 16 10:34:39 host postfix/cleanup[26647]: A442636F4E08: message-id=<A7F31C6BA7A3024C8E805A815F5394B07E42EDCDAE@FWEXN065V5.nation.radix>
          Jun 16 10:34:38 host postfix/smtpd[26643]: A442636F4E08: client=mail-it0-f70.google.com[209.85.214.70]
          Jun 18 17:20:07 host postfix/qmgr[5216]: D830936F4187: removed
          Jun 18 17:19:47 host postfix/smtpd[26963]: D830936F4187: client=mail-io0-f200.google.com[209.85.223.200]
          Jun 18 17:19:48 host postfix/cleanup[26945]: D830936F4187: message-id=<743C78C714FB92458715463CFD0F5CDD01CB40B46176@FWEXN066V6.nation.radix>
          Jun 18 17:19:48 host postfix/qmgr[5216]: D830936F4187: from=<prvs=9709ca2f8=HIGHERED@localhost>, size=5836, nrcpt=1 (queue active)
          Jun 18 17:20:07 host postfix/pipe[26967]: D830936F4187: to=<alaveteli@localhost>, orig_to=<#{ request_email }>, relay=alaveteli, delay=19, delays=0.49/0.02/0/19, dsn=2.0.0, status=sent (delivered via alaveteli service)
          Jun 18 17:19:40 host postfix/qmgr[5216]: 2307536F4187: removed
          Jun 18 17:19:40 host postfix/smtp[26445]: 2307536F4187: to=<HIGHERED@localhost>, relay=relay.example.com[165.12.251.25]:25, delay=1.2, delays=0.22/0/0.58/0.44, dsn=2.0.0, status=sent (250 ok:  Message 190847410 accepted)
          Jun 18 17:19:39 host postfix/qmgr[5216]: 2307536F4187: from=<#{ request_email }>, size=3074, nrcpt=1 (queue active)
          Jun 18 17:19:39 host postfix/cleanup[26945]: 2307536F4187: message-id=<ogm-+5764f60a85acc-dfd9@localhost>
          Jun 18 17:19:39 host postfix/pickup[2960]: 2307536F4187: uid=1003 from=<#{ request_email }>
          EOF

          expected_lines = <<-EOF.strip_heredoc
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: removed
          Jun 15 20:59:18 host postfix/pickup[17736]: 053EF36F5B67: uid=1003 from=<#{ request_email }>
          Jun 15 20:59:18 host postfix/cleanup[4358]: 053EF36F5B67: message-id=<#{ smtp_message_id }>
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: from=<#{ request_email }>, size=2070, nrcpt=1 (queue active)
          Jun 15 20:59:18 host postfix/smtp[3848]: 053EF36F5B67: to=<#{ body_email }>, relay=relay.example.com[165.12.251.85]:25, delay=0.98, delays=0.08/0/0.5/0.4, dsn=2.0.0, status=sent (250 ok:  Message 114541484 accepted)
          EOF

          expect(message.mail_server_logs.map(&:line)).
            to eq(expected_lines.scan(/[^\n]*\n/))
        end

        it 'finds the mail server logs associated with a resent message' do
          message = FactoryBot.create(:internal_review_request)
          body_email = message.info_request.public_body.request_email
          request_email = message.info_request.incoming_email
          request_subject = message.info_request.email_subject_request(html: false)
          smtp_message_id = 'ogm-14+537f69734b97c-1ebd@localhost'

          message.prepare_message_for_resend

          mail_message = OutgoingMailer.initial_request(
            message.info_request,
            message
          ).deliver_now

          message.record_email_delivery(
            mail_message.to_addrs.join(', '),
            mail_message.message_id,
            'resent'
          )

          resent_smtp_message_id = mail_message.message_id

          load_mail_server_logs <<-EOF.strip_heredoc
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: removed
          Jun 15 20:59:18 host postfix/pickup[17736]: 053EF36F5B67: uid=1003 from=<#{ request_email }>
          Jun 15 20:59:18 host postfix/cleanup[4358]: 053EF36F5B67: message-id=<#{ smtp_message_id }>
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: from=<#{ request_email }>, size=2070, nrcpt=1 (queue active)
          Jun 15 20:59:18 host postfix/smtp[3848]: 053EF36F5B67: to=<#{ body_email }>, relay=relay.example.com[165.12.251.85]:25, delay=0.98, delays=0.08/0/0.5/0.4, dsn=2.0.0, status=sent (250 ok:  Message 114541484 accepted)
          Jun 16 10:34:56 host postfix/qmgr[5216]: A442636F4E08: removed
          Jun 16 10:34:56 host postfix/pipe[26650]: A442636F4E08: to=<alaveteli@localhostlocalhost>, orig_to=<#{ request_email }>, relay=alaveteli, delay=18, delays=0.62/0.01/0/17, dsn=2.0.0, status=sent (delivered via alaveteli service)
          Jun 16 10:34:39 host postfix/qmgr[5216]: A442636F4E08: from=<prvs=968dc94c7=HIGHERED@localhost>, size=19457, nrcpt=1 (queue active)
          Jun 16 10:34:39 host postfix/cleanup[26647]: A442636F4E08: message-id=<A7F31C6BA7A3024C8E805A815F5394B07E42EDCDAE@FWEXN065V5.nation.radix>
          Jun 16 10:34:38 host postfix/smtpd[26643]: A442636F4E08: client=mail-it0-f70.google.com[209.85.214.70]
          Jun 18 17:20:07 host postfix/qmgr[5216]: D830936F4187: removed
          Jun 18 17:19:47 host postfix/smtpd[26963]: D830936F4187: client=mail-io0-f200.google.com[209.85.223.200]
          Jun 18 17:19:48 host postfix/cleanup[26945]: D830936F4187: message-id=<743C78C714FB92458715463CFD0F5CDD01CB40B46176@FWEXN066V6.nation.radix>
          Jun 18 17:19:48 host postfix/qmgr[5216]: D830936F4187: from=<prvs=9709ca2f8=HIGHERED@localhost>, size=5836, nrcpt=1 (queue active)
          Jun 18 17:20:07 host postfix/pipe[26967]: D830936F4187: to=<alaveteli@localhost>, orig_to=<#{ request_email }>, relay=alaveteli, delay=19, delays=0.49/0.02/0/19, dsn=2.0.0, status=sent (delivered via alaveteli service)
          Jun 18 17:19:40 host postfix/qmgr[5216]: 2307536F4187: removed
          Jun 18 17:19:40 host postfix/smtp[26445]: 2307536F4187: to=<HIGHERED@localhost>, relay=relay.example.com[165.12.251.25]:25, delay=1.2, delays=0.22/0/0.58/0.44, dsn=2.0.0, status=sent (250 ok:  Message 190847410 accepted)
          Jun 18 17:19:39 host postfix/qmgr[5216]: 2307536F4187: from=<#{ request_email }>, size=3074, nrcpt=1 (queue active)
          Jun 18 17:19:39 host postfix/cleanup[26945]: 2307536F4187: message-id=<#{ resent_smtp_message_id }>
          Jun 18 17:19:39 host postfix/pickup[2960]: 2307536F4187: uid=1003 from=<#{ request_email }>
          EOF

          expected_lines = <<-EOF.strip_heredoc
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: removed
          Jun 15 20:59:18 host postfix/pickup[17736]: 053EF36F5B67: uid=1003 from=<#{ request_email }>
          Jun 15 20:59:18 host postfix/cleanup[4358]: 053EF36F5B67: message-id=<#{ smtp_message_id }>
          Jun 15 20:59:18 host postfix/qmgr[5216]: 053EF36F5B67: from=<#{ request_email }>, size=2070, nrcpt=1 (queue active)
          Jun 15 20:59:18 host postfix/smtp[3848]: 053EF36F5B67: to=<#{ body_email }>, relay=relay.example.com[165.12.251.85]:25, delay=0.98, delays=0.08/0/0.5/0.4, dsn=2.0.0, status=sent (250 ok:  Message 114541484 accepted)
          Jun 18 17:19:40 host postfix/qmgr[5216]: 2307536F4187: removed
          Jun 18 17:19:40 host postfix/smtp[26445]: 2307536F4187: to=<HIGHERED@localhost>, relay=relay.example.com[165.12.251.25]:25, delay=1.2, delays=0.22/0/0.58/0.44, dsn=2.0.0, status=sent (250 ok:  Message 190847410 accepted)
          Jun 18 17:19:39 host postfix/qmgr[5216]: 2307536F4187: from=<#{ request_email }>, size=3074, nrcpt=1 (queue active)
          Jun 18 17:19:39 host postfix/cleanup[26945]: 2307536F4187: message-id=<#{ resent_smtp_message_id }>
          Jun 18 17:19:39 host postfix/pickup[2960]: 2307536F4187: uid=1003 from=<#{ request_email }>
          EOF

          expect(message.mail_server_logs.map(&:line)).
            to eq(expected_lines.scan(/[^\n]*\n/))
        end

      end

    end

    describe '#delivery_status' do

      it 'returns a failed status if the message send failed' do
        message = FactoryBot.create(:failed_sent_request_event).outgoing_message
        status = MailServerLog::DeliveryStatus.new(:failed)
        expect(message.delivery_status).to eq(status)
      end

      it 'returns an unknown delivery status if there are no mail logs' do
        message = FactoryBot.create(:initial_request)
        allow(message).to receive(:mail_server_logs).and_return([])
        status = MailServerLog::DeliveryStatus.new(:unknown)
        expect(message.delivery_status).to eq(status)
      end

      it 'returns an unknown delivery status if we cannot parse a status' do
        log_lines = <<-EOF.strip_heredoc.split("\n")
        junk
        garbage
        EOF
        logs = log_lines.map { |line| MailServerLog.new(line: line) }
        message = FactoryBot.create(:initial_request)
        allow(message).to receive(:mail_server_logs).and_return(logs)
        status = MailServerLog::DeliveryStatus.new(:unknown)
        expect(message.delivery_status).to eq(status)
      end

      context 'when the MTA is exim' do

        before do
          allow(AlaveteliConfiguration).
            to receive(:mta_log_type).and_return('exim')
        end

        it 'returns a delivery status for the most recent line with a parsable status' do
          log_lines = <<-EOF.strip_heredoc.split("\n")
          2015-10-30 19:24:16 [17814] 1ZsFHb-0004dK-SM <= request-123-abc987@example.net U=alaveteli P=local S=2252 id=ogm-14+537f69734b97c-1ebd@localhost T="FOI Request about stuff" from <request-123-abc987@example.net> for authority@example.com authority@example.com
          2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM => authority@example.com F=<request-123-abc987@example.net> P=<request-123-abc987@example.net> R=dnslookup T=remote_smtp S=2297 H=cluster2.gsi.messagelabs.com [127.0.0.1]:25 X=TLS1.2:DHE_RSA_AES_128_CBC_SHA1:128 CV=no DN="C=US,ST=California,L=Mountain View,O=Symantec Corporation,OU=Symantec.cloud,CN=mail221.messagelabs.com" C="250 ok 1446233056 qp 26062 server-4.tower-221.messagelabs.com!1446233056!7679409!1" QT=1s DT=0s
          2015-10-30 19:24:16 [17817] 1ZsFHb-0004dK-SM junk
          EOF
          logs = log_lines.map { |line| MailServerLog.new(line: line) }
          message = FactoryBot.create(:initial_request)
          allow(message).to receive(:mail_server_logs).and_return(logs)
          status = MailServerLog::DeliveryStatus.new(:delivered)
          expect(message.delivery_status).to eq(status)
        end

        it 'returns a delivery status for a redelivered message' do
          log_lines = <<-EOF.strip_heredoc.split("\n")
          2016-04-06 12:01:07 [14928] 1anlCt-0003sm-LG <= request-326806-hk82iwn7@localhost U=alaveteli P=local S=1923 id=ogm-531356+5704ec7388370-456e@localhost T="Freedom of Information request - Some Information" from <request-326806-hk82iwn7@localhost> for foi@example.net foi@example.net
          2016-04-06 12:01:08 [14933] 1anlCt-0003sm-LG ** foi@example.net F=<request-326806-hk82iwn7@localhost>: all relevant MX records point to non-existent hosts
          2016-04-06 12:01:08 [14933] 1anlCt-0003sm-LG ** foi@example.net F=<request-326806-hk82iwn7@localhost>: all relevant MX records point to non-existent hosts
          2016-04-06 12:01:08 [14935] 1anlCu-0003st-1p <= <> R=1anlCt-0003sm-LG U=Debian-exim P=local S=2934 T="Mail delivery failed: returning message to sender" from <> for request-326806-hk82iwn7@localhost
          2016-04-22 13:13:03 [24970] 1atZxH-0006Uk-KF <= request-326806-hk82iwn7@localhost U=alaveteli P=local S=1923 id=ogm-531356+571a154f7b7c5-2a7e@localhost T="Freedom of Information request - Some Information" from <request-326806-hk82iwn7@localhost> for foi@example.net foi@example.net
          2016-04-22 13:24:41 [29720] 1atZxH-0006Uk-KF => foi@example.net F=<request-326806-hk82iwn7@localhost> P=<request-326806-hk82iwn7@localhost> R=dnslookup T=remote_smtp S=1975 H=mail.example.net [213.161.89.103]:25 X=TLS1.2:DHE_RSA_AES_256_CBC_SHA256:256 CV=no DN="ST=CA,L=CU,O=TREND,OU=IMSVA,CN=IMSVA.TREND" C="250 2.0.0 Ok: queued as 8D6E6AA66C" QT=11m38s DT=0s
          EOF
          logs = log_lines.map { |line| MailServerLog.new(line: line) }
          message = FactoryBot.create(:initial_request)
          allow(message).to receive(:mail_server_logs).and_return(logs)
          status = MailServerLog::DeliveryStatus.new(:delivered)
          expect(message.delivery_status).to eq(status)
        end

        it 'returns a delivery status for a bounced message' do
          log_lines = <<-EOF.strip_heredoc.split("\n")
          2016-04-06 12:01:07 [14928] 1anlCt-0003sm-LG <= request-326806-hk82iwn7@localhost U=alaveteli P=local S=1923 id=ogm-326806+5704ec7388370-456e@localhost.com T="Freedom of Information request - Computers" from <request-326806-hk82iwn7@localhost> for foi@authority.net foi@authority.net
          2016-04-06 12:01:08 [14933] 1anlCt-0003sm-LG ** foi@authority.net F=<request-326806-hk82iwn7@localhost>: all relevant MX records point to non-existent hosts
          2016-04-06 12:01:08 [14933] 1anlCt-0003sm-LG ** foi@authority.net F=<request-326806-hk82iwn7@localhost>: all relevant MX records point to non-existent hosts
          2016-04-06 12:01:08 [14935] 1anlCu-0003st-1p <= <> R=1anlCt-0003sm-LG U=Debian-exim P=local S=2934 T="Mail delivery failed: returning message to sender" from <> for request-326806-hk82iwn7@localhost
          EOF
          logs = log_lines.map { |line| MailServerLog.new(line: line) }
          message = FactoryBot.create(:initial_request)
          allow(message).to receive(:mail_server_logs).and_return(logs)
          status = MailServerLog::DeliveryStatus.new(:failed)
          expect(message.delivery_status).to eq(status)
        end

      end

    end

    context 'when the MTA is postfix' do

      before do
        allow(AlaveteliConfiguration).
          to receive(:mta_log_type).and_return('postfix')
      end

      it 'returns a delivery status for a deferred message' do
        log_lines = <<-EOF.strip_heredoc.split("\n")
        Oct  3 16:39:35 host postfix/pickup[2257]: CB55836EE58C: uid=1003 from=<foi+request-14-e0e09f97@example.com>
        Oct  3 16:39:35 host postfix/cleanup[7674]: CB55836EE58C: message-id=<ogm-15+506bdda7a4551-20ee@example.com>
        Oct  3 16:39:35 host postfix/qmgr[1673]: 9634B16F7F7: from=<foi+request-10-1234@example.com>, size=368, nrcpt=1 (queue active)
        Oct  3 16:39:35 host postfix/qmgr[15615]: CB55836EE58C: from=<foi+request-14-e0e09f97@example.com>, size=1695, nrcpt=1 (queue active)
        Oct  3 16:39:38 host postfix/smtp[7676]: CB55836EE58C: to=<foi@some.gov.au>, relay=aspmx.l.google.com[74.125.25.27]:25, delay=2.5, delays=0.13/0.02/1.7/0.59, dsn=2.0.0, status=sent (250 2.0.0 OK 1349246383 j9si1676296paw.328)
        Oct  3 16:39:38 host postfix/smtp[1681]: 9634B16F7F7: to=<kdent@example.com>, relay=none, delay=46, status=deferred (connect to 216.150.150.131[216.150.150.131]: No route to host)
        Oct  3 16:39:38 host postfix/qmgr[15615]: CB55836EE58C: removed
        EOF
        logs = log_lines.map { |line| MailServerLog.new(line: line) }
        message = FactoryBot.create(:initial_request)
        allow(message).to receive(:mail_server_logs).and_return(logs)
        status = MailServerLog::DeliveryStatus.new(:sent)
        expect(message.delivery_status).to eq(status)
      end

      it 'returns a delivery status for a bounced message' do
        log_lines = <<-EOF.strip_heredoc.split("\n")
        Nov 19 22:56:04 host postfix/qmgr[5216]: 3742D3602065: removed
        Nov 19 22:56:04 host postfix/bounce[26532]: 3742D3602065: sender non-delivery notification: 4301E3602066
        Nov 19 22:56:04 host postfix/smtp[26054]: 3742D3602065: to=<foi@example.com>, relay=none, delay=0.06, delays=0.05/0/0/0, dsn=5.4.4, status=bounced (Host or domain name not found. Name service error for name=example.com type=A: Host not found)
        Nov 19 22:56:04 host postfix/qmgr[5216]: 3742D3602065: from=<foi+request@localhost>, size=2062, nrcpt=1 (queue active)
        Nov 19 22:56:04 host postfix/cleanup[26052]: 3742D3602065: message-id=<ogm-2856+58d41e800-3ee8@localhost>
        Nov 19 22:56:04 host postfix/pickup[27268]: 3742D3602065: uid=1003 from=<foi+request@localhost>
        EOF
        logs = log_lines.map { |line| MailServerLog.new(line: line) }
        message = FactoryBot.create(:initial_request)
        allow(message).to receive(:mail_server_logs).and_return(logs)
        status = MailServerLog::DeliveryStatus.new(:failed)
        expect(message.delivery_status).to eq(status)
      end

      it 'returns a delivery status for the most recent line with a parsable status' do
        log_lines = <<-EOF.strip_heredoc.split("\n")
        Oct  3 16:39:35 host postfix/pickup[2257]: CB55836EE58C: uid=1003 from=<foi+request-14-e0e09f97@example.com>
        Oct  3 16:39:35 host postfix/cleanup[7674]: CB55836EE58C: message-id=<ogm-15+506bdda7a4551-20ee@example.com>
        Oct  3 16:39:35 host postfix/qmgr[15615]: CB55836EE58C: from=<foi+request-14-e0e09f97@example.com>, size=1695, nrcpt=1 (queue active)
        Oct  3 16:39:38 host postfix/smtp[7676]: CB55836EE58C: to=<foi@some.gov.au>, relay=aspmx.l.google.com[74.125.25.27]:25, delay=2.5, delays=0.13/0.02/1.7/0.59, dsn=2.0.0, status=sent (250 2.0.0 OK 1349246383 j9si1676296paw.328)
        Oct  3 16:39:38 host postfix/qmgr[15615]: CB55836EE58C: removed
        EOF
        logs = log_lines.map { |line| MailServerLog.new(line: line) }
        message = FactoryBot.create(:initial_request)
        allow(message).to receive(:mail_server_logs).and_return(logs)
        status = MailServerLog::DeliveryStatus.new(:delivered)
        expect(message.delivery_status).to eq(status)
      end

      it 'returns a delivery status for a redelivered message' do
        log_lines = <<-EOF.strip_heredoc.split("\n")
        Nov 19 22:56:04 host postfix/qmgr[5216]: 3742D3602065: removed
        Nov 19 22:56:04 host postfix/bounce[26532]: 3742D3602065: sender non-delivery notification: 4301E3602066
        Nov 19 22:56:04 host postfix/smtp[26054]: 3742D3602065: to=<foi@example.com>, relay=none, delay=0.06, delays=0.05/0/0/0, dsn=5.4.4, status=bounced (Host or domain name not found. Name service error for name=example.com type=A: Host not found)
        Nov 19 22:56:04 host postfix/qmgr[5216]: 3742D3602065: from=<foi+request@localhost>, size=2062, nrcpt=1 (queue active)
        Nov 19 22:56:04 host postfix/cleanup[26052]: 3742D3602065: message-id=<ogm-2856+58d41e800-3ee8@localhost>
        Nov 19 22:56:04 host postfix/pickup[27268]: 3742D3602065: uid=1003 from=<foi+request@localhost>
        Nov 20 16:39:35 host postfix/pickup[2257]: CB55836EE58C: uid=1003 from=<foi+request@localhost>
        Nov 20 16:39:35 host postfix/cleanup[7674]: CB55836EE58C: message-id=<ogm-2856+58d41e800-3ee8@localhost>
        Nov 20 16:39:35 host postfix/qmgr[15615]: CB55836EE58C: from=<foi+request@localhost>, size=1695, nrcpt=1 (queue active)
        Nov 20 16:39:38 host postfix/smtp[7676]: CB55836EE58C: to=<foi@some.gov.au>, relay=aspmx.l.google.com[74.125.25.27]:25, delay=2.5, delays=0.13/0.02/1.7/0.59, dsn=2.0.0, status=sent (250 2.0.0 OK 1349246383 j9si1676296paw.328)
        Nov 20 16:39:38 host postfix/qmgr[15615]: CB55836EE58C: removed
        EOF
        logs = log_lines.map { |line| MailServerLog.new(line: line) }
        message = FactoryBot.create(:initial_request)
        allow(message).to receive(:mail_server_logs).and_return(logs)
        status = MailServerLog::DeliveryStatus.new(:delivered)
        expect(message.delivery_status).to eq(status)
      end
    end

  end

  describe '#prepare_message_for_resend' do
    let(:outgoing_message) { FactoryBot.build(:initial_request) }
    subject { outgoing_message.prepare_message_for_resend }

    it 'raises an error if it receives an unexpected message_type' do
      allow(outgoing_message).to receive(:message_type).and_return('fake')
      expect{ subject }.to raise_error(RuntimeError)
    end

    it 'raises an error if it receives an unexpected status' do
      outgoing_message.status = 'ready'
      expect{ subject }.to raise_error(RuntimeError)
    end

    it 'sets status to "ready" if the current status is "sent"' do
      outgoing_message.status = 'sent'
      expect{ subject }.to change{ outgoing_message.status }.to('ready')
    end

    it 'sets status to "ready" if the current status is "failed"' do
      outgoing_message.status = 'failed'
      expect{ subject }.to change{ outgoing_message.status }.to('ready')
    end

  end

  describe '#record_email_failure' do
    let(:outgoing_message) { FactoryBot.create(:initial_request) }
    subject { outgoing_message.record_email_failure('Exception#message') }

    it 'sets the status to "failed"' do
      subject
      expect(outgoing_message.status).to eq 'failed'
    end

    it 'records the reason for the failure in the event log' do
      subject
      event = outgoing_message.info_request.info_request_events.last
      expect(event.event_type).to eq('send_error')
      expect(event.params[:reason]).to eq('Exception#message')
    end

    it 'sets described_state to "error_message"' do
      subject
      expect(outgoing_message.info_request.described_state).
        to eq 'error_message'
    end

    it 'updates OutgoingMessage#last_sent_at' do
      expect{ subject }.to change{ outgoing_message.last_sent_at }
    end

  end

end

RSpec.describe OutgoingMessage, " when making an outgoing message" do

  before do
    @om = outgoing_messages(:useless_outgoing_message)
    @outgoing_message = OutgoingMessage.new({
                                              status: 'ready',
                                              message_type: 'initial_request',
                                              body: 'This request contains a foo@bar.com email address',
                                              last_sent_at: Time.zone.now,
                                              what_doing: 'normal_sort'
    })
  end

  it "should not index the email addresses" do
    # also used for track emails
    expect(@outgoing_message.get_text_for_indexing).not_to include("foo@bar.com")
  end


  it "should include email addresses in outgoing messages" do
    expect(@outgoing_message.body).to include("foo@bar.com")
  end

  it 'should produce the expected text for an internal review request' do
    public_body = FactoryBot.build(:public_body, name: 'A test public body')
    info_request = FactoryBot.build(:info_request,
                                    title: 'A test title',
                                    public_body: public_body)
    outgoing_message = OutgoingMessage.new({
                                             status: 'ready',
                                             message_type: 'followup',
                                             what_doing: 'internal_review',
                                             info_request: info_request
    })
    expected_text = "Dear A test public body,\n\nPlease pass this on to the person who conducts Freedom of Information reviews.\n\nI am writing to request an internal review of A test public body's handling of my FOI request 'A test title'.\n\n[ GIVE DETAILS ABOUT YOUR COMPLAINT HERE ]\n\nA full history of my FOI request and all correspondence is available on the Internet at this address: http://test.host/request/a_test_title\n\nYours faithfully,"
    expect(outgoing_message.body).to eq(expected_text)
  end

end

RSpec.describe OutgoingMessage, "when validating the format of the message body" do

  it 'should handle a salutation with a bracket in it' do
    outgoing_message = FactoryBot.build(:initial_request)
    allow(outgoing_message).to receive(:get_salutation).and_return("Dear Bob (Robert,")
    expect { outgoing_message.valid? }.not_to raise_error
  end

end

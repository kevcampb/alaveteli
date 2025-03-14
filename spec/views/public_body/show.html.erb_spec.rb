require 'spec_helper'

RSpec.describe "public_body/show" do
  before do
    @pb = mock_model(PublicBody,
                     name: 'Test Quango',
                     short_name: 'tq',
                     url_name: 'testquango',
                     notes: '',
                     tags: [],
                     eir_only?: nil,
                     info_requests: [1, 2, 3, 4], # out of sync with Xapian
                     publication_scheme: '',
                     disclosure_log: '',
                     calculated_home_page: '')
    allow(@pb).to receive(:not_subject_to_law?).and_return(false)
    allow(@pb).to receive(:is_requestable?).and_return(true)
    allow(@pb).to receive(:special_not_requestable_reason?).and_return(false)
    allow(@pb).to receive(:has_notes?).and_return(false)
    allow(@pb).to receive(:has_tag?).and_return(false)
    allow(@pb).to receive(:tag_string).and_return('')
    allow(@pb).to receive(:legislation).and_return(Legislation.default)
    @xap = double(ActsAsXapian::Search, matches_estimated: 2)
    allow(@xap).to receive(:results).and_return([
      { model: mock_event },
      { model: mock_event }
    ])

    assign(:public_body, @pb)
    assign(:track_thing,
           mock_model(TrackThing,
                      track_type: 'public_body_updates',
                      public_body: @pb,
                      params: {})
    )
    assign(:xapian_requests, @xap)
    assign(:page, 1)
    assign(:per_page, 10)
    assign(:number_of_visible_requests, 4)
  end

  it "should be successful" do
    render
    expect(controller.response).to be_successful
  end

  it "should show the body's name" do
    render
    expect(response).to have_css('h1', text: "Test Quango")
  end

  it "should tell total number of requests" do
    render
    expect(response).to match "4 requests"
  end

  it "should cope with no results" do
    assign(:number_of_visible_requests, 0)
    render
    expect(response).
      to have_css('p',
                  text: "Nobody has made any Freedom of Information requests")
  end

  it "should cope with Xapian being down" do
    assign(:xapian_requests, nil)
    render
    expect(response).to match "The search index is currently offline"
  end

  it 'allows the user to make an FOI request' do
    render
    expect(rendered).
      to have_content('Make a Freedom of Information request to this authority')
  end

  context 'the public body is tagged as "foi_no"' do

    let(:public_body) { FactoryBot.build(:public_body, tag_string: 'foi_no') }

    it 'displays a message that the authority is not obliged to respond' do
      assign(:public_body, public_body)
      render
      expect(rendered).
        to have_content('This authority is not subject to FOI law, so is ' \
                        'not legally obliged to respond')
    end

  end

  context 'the public body is tagged as "eir_only"' do

    let(:public_body) { FactoryBot.build(:public_body, tag_string: 'eir_only') }

    it 'displays a message that the authority is only open to environmental requests' do
      assign(:public_body, public_body)
      render
      expect(rendered).
        to have_content('You only have a right in law to access information ' \
                        'about the environment from this authority')
    end

    it 'allows the user to make an EIR request' do
      assign(:public_body, public_body)
      render
      expect(rendered).
        to have_content('Make an Environmental Information Regulations ' \
                        'request to this authority')
    end
  end

  context 'the public body is tagged as "eir_only" and "foi_no"' do

    let(:public_body) do
      FactoryBot.build(:public_body, tag_string: 'eir_only foi_no')
    end

    it 'displays a message that the authority is only open to environmental requests' do
      assign(:public_body, public_body)
      render
      expect(rendered).
        to have_content('You only have a right in law to access information ' \
                        'about the environment from this authority')
    end

  end

  context 'the public body is tagged as "defunct"' do

    let(:public_body) do
      FactoryBot.build(:public_body, tag_string: 'defunct')
    end

    it 'displays a message that the authority is defunct' do
      assign(:public_body, public_body)
      render
      expect(rendered).
        to have_content('This authority no longer exists, so you cannot make ' \
                        'a request to it.')
    end

  end

end

def mock_event
  mock_model(
    InfoRequestEvent,
    info_request: mock_model(
      InfoRequest,
      title: 'Title',
      url_title: 'title',
      display_status: 'waiting_response',
      calculate_status: 'waiting_response',
      public_body: @pb,
      is_external?: false,
      user: mock_model(
        User,
        name: 'Test User',
        url_name: 'testuser')
    ),
    incoming_message: nil,
    is_incoming_message?: false,
    outgoing_message: nil,
    is_outgoing_message?: false,
    comment: nil,
    is_comment?: false,
    event_type: 'sent',
    created_at: Time.zone.now - 4.days,
    search_text_main: ''
  )
end

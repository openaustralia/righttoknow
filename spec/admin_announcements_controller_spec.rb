# frozen_string_literal: true

# The admin announcement form, backported from
# https://github.com/mysociety/alaveteli/pull/9644 (see
# lib/announcement_patches.rb).
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)
require File.expand_path('support/announcement_factory', __dir__)

RSpec.describe AdminAnnouncementsController, type: :controller do
  # Announcements record who last changed them, so unlike most admin
  # controllers this needs a signed in user, not only basic auth.
  let(:admin_user) { FactoryBot.create(:admin_user) }

  before(:each) do
    basic_auth_login(@request)
    sign_in admin_user
  end

  describe 'GET index' do
    before { get :index }

    it 'returns a successful response' do
      expect(response).to be_successful
    end

    it 'assigns the announcements' do
      expect(assigns[:announcements]).to all(be_a(Announcement))
    end
  end

  describe 'GET new' do
    before { get :new }

    it 'returns a successful response' do
      expect(response).to be_successful
    end

    it 'assigns a default style announcement' do
      expect(assigns[:announcement]).to be_default_style
    end
  end

  describe 'POST #create' do
    let(:params) do
      {
        announcement: {
          visibility: 'everyone',
          style: 'yellow',
          title: 'Hello',
          rich_body: 'New body'
        }
      }
    end

    context 'with valid params' do
      before { post :create, params: params }

      it 'creates the announcement' do
        # Found again from the database, so this checks what was saved and
        # not the object the controller built
        announcement = Announcement.find(assigns[:announcement].id)
        expect(announcement).to be_yellow_style
        expect(announcement.rich_body.to_plain_text).to eq('New body')
      end

      it 'redirects to the index' do
        expect(response).to redirect_to(admin_announcements_path)
      end
    end

    context 'without a body' do
      before do
        params[:announcement][:rich_body] = ''
        post :create, params: params
      end

      it 're-renders the form' do
        expect(response).to render_template(:new)
      end
    end
  end

  describe 'PATCH #update' do
    let(:announcement) { FactoryBot.create(:announcement) }

    before do
      patch :update, params: {
        id: announcement.id,
        announcement: { style: 'green' }
      }
    end

    it 'updates the style' do
      expect(announcement.reload).to be_green_style
    end
  end

  describe 'PATCH #update with only a body' do
    let(:announcement) do
      FactoryBot.create(:announcement, style: 'red', rich_body: 'Old body')
    end

    before do
      patch :update, params: {
        id: announcement.id,
        announcement: { rich_body: 'New body' }
      }
    end

    it 'saves the new body' do
      expect(Announcement.find(announcement.id).rich_body.to_plain_text)
        .to eq('New body')
    end

    it 'leaves the style alone' do
      expect(Announcement.find(announcement.id)).to be_red_style
    end
  end
end

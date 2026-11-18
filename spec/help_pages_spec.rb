# frozen_string_literal: true

# Renders the theme's help pages through the real routes and views.
#
# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(
  File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper')
)

RSpec.describe 'Help pages', type: :request do
  describe 'GET /help/contact' do
    before { get '/help/contact' }

    it 'shows the help sidebar' do
      expect(response.body).to include('id="right_column_flip"')
      expect(response.body).to include('<h2>Help pages</h2>')
    end

    it 'does not link the sidebar contact promo back to itself' do
      expect(response.body).not_to include('<h2 id="contact"')
    end

    it 'still shows the contact form' do
      expect(response.body).to include('name="contact[message]"')
      expect(response.body).to include('Send message to the charity')
    end
  end

  describe 'POST /help/contact with an empty form' do
    before { post '/help/contact', params: { submitted_contact_form: 1, contact: { name: '', email: '', subject: '', message: '' } } }

    it 're-renders the form inside the sidebar layout with the errors' do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="right_column_flip"')
      expect(response.body).to include('name="contact[message]"')
    end
  end

  describe 'GET /help/about' do
    it 'keeps the sidebar contact promo on other help pages' do
      get '/help/about'

      expect(response.body).to include('<h2 id="contact"')
    end
  end

  describe 'GET /help/alaveteli' do
    before { get '/help/alaveteli' }

    it 'describes the software' do
      expect(response.body).to include('This website is powered by Alaveteli')
    end

    it 'does not offer to help set up Alaveteli elsewhere' do
      expect(response.body).not_to include('set up an Alaveteli website')
      expect(response.body).not_to include('hello@alaveteli.org')
    end
  end

  describe 'GET /help/alaveteli with a country_name' do
    before { get '/help/alaveteli', params: { country_name: 'Elsewhere' } }

    it 'does not ask whether people want a site in their country' do
      expect(response.body).not_to include('Would you like to see a website like this in your country?')
    end
  end
end

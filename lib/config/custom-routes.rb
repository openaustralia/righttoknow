# Here you can override or add to the pages in the core website

Rails.application.routes.draw do
  # Additional help page example
  # get '/help/help_out' => 'help#help_out'
  get '/help/house_rules' => 'help#house_rules'

  # We used to have a dedicated people page which was made in this theme.
  # Now that same information has been merged into the statistics page
  # in the main project there is no need for our version. Just to be
  # safe let's redirect the old url
  get '/people' => redirect('statistics#people')
end

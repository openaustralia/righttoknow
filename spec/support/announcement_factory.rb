# frozen_string_literal: true

# Core's announcement factory sets the legacy `content`. With this theme's
# announcement patches an announcement is only valid with a rich_body.
FactoryBot.modify do
  factory :announcement do
    rich_body { 'We’re delighted to announce we’ve rolled out the new projects' }
  end
end

# frozen_string_literal: true

# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

RSpec.describe FoiAttachmentMaskJob, type: :job do
  let(:attachment) { FactoryBot.create(:body_text) }
  let(:strategy) { described_class.new(attachment).lock_strategy }

  it 'keeps the host uniqueness strategy' do
    expect(strategy).to be_a(ActiveJob::Uniqueness::Strategies::UntilAndWhileExecuting)
  end

  it 'caps the runtime lock at 30 minutes' do
    expect(strategy.runtime_lock_ttl).to eq(30.minutes.in_milliseconds)
  end

  it 'hands runtime conflicts to the stranded-lock detector' do
    expect(strategy.on_runtime_conflict).to eq(MaskJobRuntimeConflict)
  end

  it 'leaves the enqueue lock at the gem default of a day' do
    expect(strategy.lock_ttl).to eq(1.day.in_milliseconds)
  end

  it 'keeps the host on_conflict: :log for enqueue conflicts' do
    expect(strategy.on_conflict).to eq(:log)
  end
end

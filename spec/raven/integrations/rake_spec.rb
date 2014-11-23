require 'rake'

describe 'Rake tasks' do

  it 'should capture exceptions in Rake tasks' do
    expect(`cd spec/support && bundle exec rake raise_exception 2>&1`).to match(/Sending event/)
  end

end

require 'chef_helper'

# NOTE: These specs do not verify whether the code actually ran
# Nor whether the resource inside of the recipe was notified correctly.
# At this moment they only verify whether the expected commands are passed
# to the bash block.
#

describe 'gitlab::database-migrations' do
  let(:chef_run) { ChefSpec::SoloRunner.converge('gitlab::default') }

  before do
    allow(Gitlab).to receive(:[]).and_call_original
  end

  context 'when migration should run' do
    before do
      allow_any_instance_of(OmnibusHelper).to receive(:not_listening?).and_return(false)
    end

    let(:bash_block) { chef_run.bash('migrate gitlab-rails database') }

    it 'runs the migrations' do
      expect(chef_run).to run_bash('migrate gitlab-rails database')
    end

    context 'places the log file' do
      it 'in a default location' do
        path = Regexp.escape("/var/log/gitlab/gitlab-rails/gitlab-rails-db-migrate-$(date +%Y-%m-%d-%H-%M-%S).log")
        expect(bash_block.code).to match(/#{path}/)
      end

      it 'in a custom location' do
        stub_gitlab_rb(gitlab_rails: { log_directory: "/tmp" })
        path = %(/tmp/gitlab-rails-db-migrate-)
        expect(bash_block.code).to match(/#{path}/)
      end
    end

    context 'with auto_migrate off' do
      before { stub_gitlab_rb(gitlab_rails: { auto_migrate: false }) }

      it 'skips running the migrations' do
        expect(chef_run).not_to run_bash('migrate gitlab-rails database')
      end
    end

    it 'runs with the initial_root_password in the environment' do
      stub_gitlab_rb(gitlab_rails: { initial_root_password: '123456789' })
      expect(chef_run).to run_bash('migrate gitlab-rails database').with(
        environment: { 'GITLAB_ROOT_PASSWORD' => '123456789' }
      )
    end

    it 'runs with the initial_root_password and initial_shared_runners_registration_token in the environment' do
      stub_gitlab_rb(
        gitlab_rails: { initial_root_password: '123456789', initial_shared_runners_registration_token: '987654321' }
      )
      expect(chef_run).to run_bash('migrate gitlab-rails database').with(
        environment: {
          'GITLAB_ROOT_PASSWORD' => '123456789',
          'GITLAB_SHARED_RUNNERS_REGISTRATION_TOKEN' => '987654321'
        }
      )
    end

    it 'triggers the gitlab:db:configure task' do
      migrate = %(/opt/gitlab/bin/gitlab-rake gitlab:db:configure 2>& 1 | tee ${log_file})
      expect(bash_block.code).to match(/#{migrate}/)
    end

    # NOTE: Test if we pass proper notifications to other resources
    it 'should notify rails cache clear resource' do
      expect(chef_run.bash('migrate gitlab-rails database')).to notify(
        'execute[clear the gitlab-rails cache]')
    end

    it 'should not notify rails cache clear resource if disabled' do
      stub_gitlab_rb(gitlab_rails: { rake_cache_clear: false })
      expect(chef_run.bash('migrate gitlab-rails database')).not_to notify(
        'execute[clear the gitlab-rails cache]')
    end
  end
end

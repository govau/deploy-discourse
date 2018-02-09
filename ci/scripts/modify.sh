#!/usr/bin/env bash

# Exit immediately if there is an error
set -e

# cause a pipeline (for example, curl -s http://sipb.mit.edu/ | grep foo) to produce a failure return code if any command errors not just the last command of the pipeline.
set -o pipefail

# echo out each line of the shell as it executes
set -x

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cp -rf ${INPUT_DIR}/* ${OUTPUT_DIR}

# Copy the cf run scripts into the output dir
cp ${SCRIPT_DIR}/../../cf_run_app_discourse.sh \
  ${SCRIPT_DIR}/../../cf_run_app_sidekiq.sh \
  ${SCRIPT_DIR}/../../vcap_services_as_envs.py \
  ${OUTPUT_DIR}

# Copy the manifests into the output dir.
cp ${SCRIPT_DIR}/../../manifest-* ${OUTPUT_DIR}

# Modify discourse so it will run on cf
pushd ${OUTPUT_DIR}
  # Discourse requires the services to be available during assets precompilation,
  # however in cloud foundry staging they are not yet bound to the service.
  # This means we either have to run `rake assets:precompile` before `cf push`,
  # or we use live compilation. For now we are using the second option.
  sed -i.bak  's/config.public_file_server.enabled.*/config.public_file_server.enabled = true/g' config/environments/production.rb
  sed -i.bak  's/config.assets.compile.*/config.assets.compile = true/g' config/environments/production.rb

  # Trick discourse and the ruby_buildpack that we've precompiled assets:
  # - Discourse checks for a file at startup: https://github.com/discourse/discourse/blob/master/config/initializers/100-verify_config.rb#L19
  # - The ruby buildpack should skip `rake assets:precompile` if a file is
  #   present: https://github.com/cloudfoundry/ruby-buildpack/blob/master/src/ruby/finalize/finalize.go#L209
  mkdir -p public/assets
  touch public/assets/applicationfoo.js public/assets/manifest-foo.json

  # Force SSL
  sed -i.bak '/Discourse::Application.configure do/a\
  config.force_ssl = true
' config/environments/production.rb

  #Add a sidekiq configuration for production mode if necessary
  if ! grep -q "production:" config/sidekiq.yml; then
  cat <<EOF >> config/sidekiq.yml
production:
  :concurrency: 5
  :queues:
    - [critical,4]
    - [default, 2]
    - [low]
EOF
  fi

  # Configure puma to work with cf
  # Delete any lines with stdout_redirect - in cloud foundry we need the logs
  # to go to stdout/stderr
  sed -i.bak '/stdout_redirect/d' config/puma.rb

  #No need to set pidfile or state_path
  sed -i.bak '/pidfile/d' config/puma.rb
  sed -i.bak '/state_path/d' config/puma.rb

  # Dont daemonize puma (it's not his fault)
  sed -i.bak  's/daemonize.*/daemonize false/g' config/puma.rb

  # Delete any setting of ports
  sed -i.bak '/port/d' config/puma.rb

  # Read the port from the PORT env var
  sed -i.bak '/daemonize/a\
  port ENV.fetch("PORT") { 3000 }
' config/puma.rb

  # Modify Imageoptim to work with our runtime which is missing a few utils
  # that the discourse image has
  sed -i.bak 's/optipng.*/optipng: false,/g' lib/file_helper.rb
  sed -i.bak 's/jpegoptim.*/jpegoptim: false,/g' lib/file_helper.rb
  sed -i.bak '/ImageOptim/a\
      gifsicle: false\,
' lib/file_helper.rb
  sed -i.bak '/ImageOptim/a\
      svgo: false\,
' lib/file_helper.rb
sed -i.bak '/ImageOptim/a\
    jhead: false\,
' lib/file_helper.rb

  # Add cf:on_first_instance rake task
cat <<EOF > lib/tasks/cf.rake
# http://docs.cloudfoundry.org/buildpacks/ruby/ruby-tips.html#rake
namespace :cf do
  desc "Only run on the first application instance"
  task :on_first_instance do
    instance_index = JSON.parse(ENV["VCAP_APPLICATION"])["instance_index"] rescue nil
    exit(0) unless instance_index == 0
  end
end
EOF

    # Remove discourse db backup job - we will expect the cf service to handle
    # backups e.g. RDS backups.
    rm app/jobs/scheduled/schedule_backup.rb
popd

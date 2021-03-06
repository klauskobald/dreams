require 'google/apis/script_v1'
require 'googleauth'
require 'env_token_store'

require 'json'
require 'fileutils'

  ##
  # Example taken from https://developers.google.com/apps-script/guides/rest/quickstart/ruby
  ##
  SCRIPT_ID = ENV['GOOGLE_APPS_SCRIPT']
  SCRIPT_FUNCTION = ENV['GOOGLE_APPS_SCRIPT_FUNCTION']
  OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
  APPLICATION_NAME = ENV['GOOGLE_APPS_NAME']
  CLIENT_SECRETS_PATH = 'client_secret.json'
  CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                               ENV['GOOGLE_APPS_SCRIPT_FUNCTION'] + ".yaml")
  SCOPE = 'https://www.googleapis.com/auth/drive'

class NewDreamAppsScript
  ##
  # Ensure valid credentials, either by restoring from the saved credentials
  # files or intitiating an OAuth2 authorization. If authorization is required,
  # the user's default browser will be launched to approve the request.
  #
  # @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
  def self.authorize
    client_id = Google::Auth::ClientId.from_hash(JSON.parse(ENV['GOOGLE_CLIENT_SECRETS']))
    token_store = EnvTokenStore.new('GOOGLE_APPS_SCRIPT_TOKEN')
    authorizer = Google::Auth::UserAuthorizer.new(
      client_id, SCOPE, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(
        base_url: OOB_URI)
      puts "Open the following URL in the browser and enter the " +
           "resulting code after authorization"
      puts url
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI)
    end
    credentials
  end

  def self.createNewDreamFolder(dreamerEmail, dreamId, dreamName)
    # Initialize the API
    service = Google::Apis::ScriptV1::ScriptService.new
    service.client_options.application_name = APPLICATION_NAME
    service.authorization = self.authorize

    # Create an execution request object.
    request = Google::Apis::ScriptV1::ExecutionRequest.new(
      function: SCRIPT_FUNCTION,
      parameters: [dreamerEmail, dreamId, dreamName]
    )

    begin
      # Make the API request.
      resp = service.run_script(SCRIPT_ID, request)

      if resp.error
        # The API executed, but the script returned an error.

        # Extract the first (and only) set of error details. The values of this
        # object are the script's 'errorMessage' and 'errorType', and an array of
        # stack trace elements.
        error = resp.error.details[0]

        puts "Script error message: #{error['errorMessage']}"

        if error['scriptStackTraceElements']
          # There may not be a stacktrace if the script didn't start executing.
          puts "Script error stacktrace:"
          error['scriptStackTraceElements'].each do |trace|
            puts "\t#{trace['function']}: #{trace['lineNumber']}"
          end
        end
      else
        response = resp.response['result']
        return response
      end
    rescue Google::Apis::ClientError => e
      # The API encountered a problem before the script started executing.
      puts "Error calling API!"
      puts sprintf('Caught error %s', e) 
    end
  end
end
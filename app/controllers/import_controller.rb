class ImportController < ApplicationController

  def index

    file = ENV['IMPORT_CSV_URL']
    if file.nil?
      puts "Error: Please set env IMPORT_CSV_URL"
    end

    counter = 0
    ignoredCounter = 0
    content  = open(file) {|f| f.read }
    CSV.parse(content, :headers => true) do |row|
      counter+=1
      email = row[0].downcase
      phone = row[1].tr('-', '')
      unless Ticket.exists?(email: email) and Ticket.exists?(id_code: phone)
          Ticket.create(:id_code => phone, :email => email)
      else
          ignoredCounter+=1
      end
    end
    puts "Found " + counter.to_s + " records"
    puts "Ignored existing " + ignoredCounter.to_s + " records"
  end

  def one
    email = params[:email]
    phone = params[:phone]
    unless Ticket.exists?(email: email) and Ticket.exists?(id_code: phone)
        Ticket.create(:id_code => phone, :email => email)
    end
  end

end

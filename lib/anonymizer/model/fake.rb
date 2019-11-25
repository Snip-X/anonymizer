# frozen_string_literal: true

# Generator to fake data
class Fake
  def self.user
    firstname = escape_characters_in_string(Faker::Name.first_name)
    lastname = escape_characters_in_string(Faker::Name.last_name)

    prepare_user_hash firstname, lastname
  end

  def self.user_bank(bank_countries_code,min_age,max_age)
    firstname = escape_characters_in_string(Faker::Name.first_name)
    lastname = escape_characters_in_string(Faker::Name.last_name)
    @bank_country=bank_countries_code
    @min_a = min_age
    @max_a = max_age
    prepare_user_hash firstname, lastname
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  def self.create_fake_user_table(database)
    database.create_table :fake_user do
      primary_key :id
      String :firstname
      String :lastname
      String :fullname
      String :birthday
      String :ancestor
      String :login
      String :email
      String :telephone
      String :company
      String :street
      String :postcode
      String :city
      String :full_address
      String :vat_id
      String :ip
      String :quote
      String :website
      String :iban
      String :swift_bic
      String :regon
      String :pesel
      String :json
    end
  end

  def self.prepare_user_hash(firstname, lastname)
     street=Faker::Address.street_name
     postcode=Faker::Address.postcode
     city= Faker::Address.city
     fulladdr= rand(1..150).to_s+" "+street+", "+postcode+" "+city
     date_of_birth = Faker::Date.birthday(min_age: @min_a, max_age: @max_a)
     unless @bank_country.nil?
	 iban=Faker::Bank.iban(country_code: @bank_country)
     else
	 iban=Faker::Bank.iban 
     end
    {
      firstname: firstname,
      lastname: lastname,
      email: Faker::Internet.email(name:"#{firstname} #{lastname}"),
      login: Faker::Internet.user_name(specifier:"#{firstname} #{lastname}",separators: %w[. _ -]),
      birthday: date_of_birth,
      fullname: "#{firstname} #{lastname}",
      telephone: Faker::PhoneNumber.cell_phone,
      ancestor: Faker::Name.name,
      company: Faker::Company.name,
      street: street,
      postcode: postcode,
      city: city,
      full_address: fulladdr,
      vat_id: Faker::Company.swedish_organisation_number,
      ip: Faker::Internet.private_ip_v4_address,
      quote: Faker::Movies::StarWars.quote,
      website: Faker::Internet.domain_name,
      iban: iban,
      swift_bic: Faker::Bank.swift_bic,
      regon: generate_regon,
      pesel: Fake::Pesel.generate,
      json: '{}'
    }
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  def self.generate_regon
    regon = district_number

    6.times do
      regon += Random.rand(0..9).to_s
    end

    sum = sum_for_wigths(regon, regon_weight)
    validation_mumber = (sum % 11 if sum % 11 != 10) || 0

    regon + validation_mumber.to_s
  end

  def self.regon_weight
    [8, 9, 2, 3, 4, 5, 6, 7]
  end

  def self.sum_for_wigths(numbers, weight_array)
    sum = 0
    numbers[0, numbers.length - 1].split('').each_with_index do |number, index|
      sum += number.to_i * weight_array[index]
    end

    sum
  end
  def self.escape_characters_in_string(string)
    pattern = /(\'|\"|\.|\*|\/|\-|\\)/
    string.gsub(pattern){|match|"\\"  + match} # <-- Trying to take the currently found match and add a \ before it I have no idea how to do that).
  end
  def self.district_number
    %w[01 03 47 49 91 93 95 97].sample
  end
end

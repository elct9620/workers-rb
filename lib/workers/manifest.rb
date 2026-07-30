# frozen_string_literal: true

require "json"

module Workers
  # `/app/<tenant>/app.json`, as the Host reads it.
  #
  # Every field is optional, so an empty object configures a Tenant
  # completely. A field the Host cannot act on makes the whole Manifest
  # invalid rather than half-applied: a Tenant serving requests under a
  # configuration its author did not write is worse than one that does not
  # serve at all.
  class Manifest
    DEFAULT_ENTRYPOINT = "App"

    # A Binding constant lives under `DB::`, so a Manifest declaration reaches
    # no name the Runtime Kit or the Tenant defines at the top level.
    BINDING_CONSTANT = /\ADB::[A-Z][A-Za-z0-9_]{0,63}\z/
    private_constant :BINDING_CONSTANT

    # No `-`, so the last `-` in `<tenant>-<database>.db` always separates the
    # two and no two Tenants resolve to one file.
    DATABASE_IDENTIFIER = /\A[a-z0-9_]{1,32}\z/
    private_constant :DATABASE_IDENTIFIER

    def self.parse(source)
      fields = JSON.parse(source)
      raise InvalidManifest, "the Manifest is not a JSON object" unless fields.is_a?(Hash)

      new(entrypoint: entrypoint_in(fields), domain: domain_in(fields), databases: databases_in(fields))
    rescue JSON::ParserError
      raise InvalidManifest, "the Manifest is not JSON"
    end

    def self.entrypoint_in(fields)
      value = fields.fetch("entrypoint", DEFAULT_ENTRYPOINT)
      raise InvalidManifest, "entrypoint is not a String" unless value.is_a?(String)

      value
    end
    private_class_method :entrypoint_in

    def self.domain_in(fields)
      value = fields["domain"]
      raise InvalidManifest, "domain is not a String" unless value.nil? || value.is_a?(String)

      value
    end
    private_class_method :domain_in

    def self.databases_in(fields)
      bindings = fields.fetch("bindings", {})
      raise InvalidManifest, "bindings is not an object" unless bindings.is_a?(Hash)

      declared = bindings.fetch("db", {})
      raise InvalidManifest, "bindings.db is not an object" unless declared.is_a?(Hash)

      declared.each { |constant, database| validate_declaration(constant, database) }
      declared.freeze
    end
    private_class_method :databases_in

    def self.validate_declaration(constant, database)
      raise InvalidManifest, "#{constant} is no Binding constant name" unless BINDING_CONSTANT.match?(constant)
      return if database.is_a?(String) && DATABASE_IDENTIFIER.match?(database)

      raise InvalidManifest, "#{constant} names no database identifier"
    end
    private_class_method :validate_declaration

    attr_reader :entrypoint, :domain, :databases

    def initialize(entrypoint:, domain:, databases:)
      @entrypoint = entrypoint
      @domain = domain
      @databases = databases
    end
  end
end

namespace :db do
  desc "Pull production database from Render into local development database"
  task pull: :environment do
    abort "Only run this in development!" unless Rails.env.development?

    render_url = ENV["RENDER_DATABASE_URL"] || read_env_file("RENDER_DATABASE_URL")
    abort "Set RENDER_DATABASE_URL in .env or environment" if render_url.blank?

    dump_file = Rails.root.join("tmp", "signals_prod.dump")
    local_db = ActiveRecord::Base.connection_db_config.configuration_hash[:database] || "signals_development"

    puts "Dumping production database..."
    system!("pg_dump", render_url, "--format=custom", "--no-owner", "--no-acl", "-f", dump_file.to_s)

    puts "Dropping and recreating #{local_db}..."
    ActiveRecord::Base.connection.disconnect!
    system!("dropdb", "--if-exists", "--force", local_db)
    system!("createdb", local_db)

    puts "Restoring into #{local_db}..."
    system("pg_restore", "--no-owner", "--no-acl", "-d", local_db, dump_file.to_s)
    # pg_restore exits non-zero on warnings (e.g. missing roles), so we don't use system! here

    puts "Cleaning up dump file..."
    FileUtils.rm_f(dump_file)

    puts "Done. Local #{local_db} now mirrors production."
  end
end

def read_env_file(key)
  env_file = Rails.root.join(".env")
  return unless env_file.exist?

  env_file.each_line do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    k, v = line.split("=", 2)
    return v.delete_prefix('"').delete_suffix('"') if k.strip == key
  end
  nil
end

def system!(*args)
  system(*args, exception: true)
end

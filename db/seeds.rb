User.find_or_create_by!(email: "jules@julescoleman.com") do |user|
  user.password = "changeme123!"
end

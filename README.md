# Rails Multitenant Template

This Rails application template sets up a new Rails application with multitenancy support using `activerecord-tenanted`, TailwindCSS for styling, and other useful features for building multitenant SaaS applications.

## Features

- **Multitenancy**: Database-level multitenancy with `activerecord-tenanted` gem
- **Styling**: TailwindCSS with dark mode support
- **AI Integration**: OpenCode configuration and Tidewave gem for development
- **Admin Interface**: CRUD interface for managing accounts/tenants
- **Testing**: Mocha for mocking in tests
- **Modern Rails**: Uses Rails 8.1 with Propshaft, Turbo, Stimulus, etc.

## Usage

### Using with Rails New

```bash
rails new myapp -m https://github.com/sevos/rails-multitenant-template/raw/master/template.rb
```

### Local Usage

Clone this repository and use the local template:

```bash
git clone https://github.com/sevos/rails-multitenant-template.git
rails new myapp -m rails-multitenant-template/template.rb
```

## What's Included

### Gems
- `activerecord-tenanted` for multitenancy
- `tailwindcss-rails` for styling
- `tidewave` for AI coding assistance (development)
- Standard Rails gems with modern defaults

### Database Configuration
- Primary database for shared data
- Tenanted account databases
- Automatic tenant creation/destruction

### Models
- `ApplicationRecord` base class
- `AccountRecord` for tenanted data
- `Account` model for tenant management

### Controllers & Views
- Admin namespace for account management
- TailwindCSS styled views with light/dark mode
- RESTful CRUD for accounts

### Configuration
- Tenancy initializer with subdomain-based tenant resolution
- Host configuration for development
- Seeds for default "dev" tenant
- OpenCode for AI coding assistant integration

### Tests
- Controller tests with Mocha mocking
- Fixtures for accounts

## Development

After generating the app:

1. Run migrations: `bin/rails db:migrate`
2. Seed the database: `bin/rails db:seed`
3. Start the server: `bin/rails server`

4. To generate models for the tenanted database, use the Rails generator with the `--database=account` option. For example: `rails g model Animal name:string --database=account` then edit the model to inherit from `AccountRecord` instead of `ApplicationRecord`. The migration will be placed in `db/account_migrate` and applied to all tenant databases when running `bin/rails db:migrate`.

5. It is advised to move the `User` and `Session` models created by `rails g authentication` to inherit from `AccountRecord` for tenant-specific data.

The app will be available at `http://myapp.localhost:3000` (adjust hosts file if needed).

Tenants are accessed via subdomains, e.g., `dev.myapp.localhost:3000`.

## Customization

- Modify `config/initializers/tenancy.rb` for different tenant resolution strategies
- Update `app/models/account.rb` for additional account fields
- Customize views in `app/views/admin/accounts/`
- Add authentication as needed

## Contributing

Contributions welcome!

## License

MIT License

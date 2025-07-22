
# Aliases
alias ll='ls -lah'
alias so='source venv/bin/activate'

# My functions
# Make Python virtual environment and activate it and upgrade pip
mkenv() {
  python -m venv venv && \
  source venv/bin/activate && \
  pip install --upgrade pip
}

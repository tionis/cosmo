(declare-project
  :name "cosmo"
  :description "dotfile managment"
  :dependencies  ["https://github.com/andrewchambers/janet-flock"
                  "https://github.com/janet-lang/sqlite3"
                  "https://github.com/janet-lang/spork"
                  "https://github.com/janet-lang/jhydro"])

(phony "dev" []
  (os/shell "while true; do inotifywait -r -e modify cosmo; jpm build; done;"))

(declare-source :source ["cosmo"])

(declare-executable
  :name "cosmo"
  :entry "cosmo/cli.janet"
  :install true)

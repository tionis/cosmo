(declare-project
  :name "cosmo"
  :description "personal dotfile manager and more"
  :dependencies  ["https://github.com/andrewchambers/janet-flock" # TODO remove flock by either integrating it or doing a pull request to spork
                  "https://github.com/janet-lang/spork"
                  "https://github.com/janet-lang/jhydro"])

(phony "dev" []
  (os/shell "while true; do inotifywait -r -e modify cosmo; jpm build; done;"))

(declare-source :source ["cosmo"])

(declare-executable
  :name "cosmo"
  :entry "cosmo/cli.janet"
  :lflags ["-export-dynamic"]
  :install true)

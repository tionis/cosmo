(use ./util)
(use ./store)

(defn local/set [key value] (cache/set (string "universal-vars/" key) value))
(defn global/set [key value] (store/set (string "universal-vars/" key) value))
(defn local/rm [key] (local/set key nil))
(defn global/rm [key] (global/set key nil))
(defn local/ls [pattern] (cache/ls (string "universal-vars/" pattern)))
(defn global/ls [pattern] (store/ls (string "universal-vars/" pattern)))
(defn local/get [key] (cache/get (string "universal-vars/" key)))
(defn global/get [key] (store/get (string "universal-vars/" key)))
(defn local/ls-contents [pattern] (cache/ls-contents pattern))
(defn global/ls-contents [pattern] (store/ls-contents pattern))

(defn export
  "returns the universal vars formatted for shell consumption as string"
  [&opt pattern]
  (def parts @[])
  (def vars (merge (global/ls-contents pattern) (local/ls-contents pattern)))
  (eachk key vars (array/push parts (string "export " key "=\"" (vars key) "\"")))
  (def node-name (cache/get "node/name"))
  (if node-name
      (array/push parts (string "export NODE_NAME=\"" node-name "\""))
      (array/push parts "export NODE_NAME=unknown"))
  (string/join parts "\n"))

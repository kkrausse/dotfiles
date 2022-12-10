(ns user
  "this is gonna be my scripting preloads file
  - utility functions/macros for common tasks
  - good import baseline - try to be almost same as babashka"
  (:require [cheshire.core :as json]
            [clojure.core.async :as async]
            [clojure.java.io :as io]
            [clojure.data.csv :as csv]
            [clojure.string :as str]
            [clojure.tools.cli :as tools.cli]
            [vlaaad.reveal.ext :as rx]
            [criterium.core :as cc]))

(apply require '([cheshire.core :as json]
                 [clojure.core.async :as async]
                 [clojure.java.io :as io]
                 [clojure.data.csv :as csv]
                 [clojure.string :as str]
                 [clojure.tools.cli :as tools.cli]
                 [vlaaad.reveal.ext :as rx]
                 [criterium.core :as cc]))

(defmacro with-lines [[linesym filename] & body]
  (assert (symbol? linesym) "first assign should be symbol")
  (assert (string? filename) "first assign should be symbol")
  `(with-open [reader# (io/reader ~filename)]
     (let [~linesym (line-seq reader#)]
       ~@body)))

#_
(tap> {:rx/command '(defaction ::intern-as-x [x]
                      #(intern 'user 'x x))})


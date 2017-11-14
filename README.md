# Card-o-matic

Card-o-matic is a small web application which takes a Pivotal API key and generates printable cards for each story in the selected iteration. It's largely based on the design of [@psd's](http://whatfettle.com/) [pivotal-cards](https://github.com/psd/pivotal-cards) bookmarklet.

You can access the online version of [Card-o-matic] (https://card-o-matic.herokuapp.com) here.

## Usage

```
bundle install
bundle exec unicorn -p 5000
```

and visit <http://localhost:5000> in your browser.

## Notes

* The iteration selection is limited to the most recent three sprints due to the time it takes to load an iteration from Pivotal's API. This might be adjusted.

## Legacy

Forked from https://github.com/JordanHatch/card-o-matic

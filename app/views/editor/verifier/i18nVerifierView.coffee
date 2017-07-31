RootComponent = require 'views/core/RootComponent'
Problem = require 'views/play/level/tome/Problem'
locale = require 'locale/locale'

I18nVerifierComponent = Vue.extend
  template: require('templates/editor/verifier/i18n-verifier-view')()
  data: ->
    allLocales: Object.keys(_.omit(locale, 'update', 'installVueI18n')).concat('rot13')
    language: 'en'
    levelSlug: location.href.match('/editor/i18n-verifier/(.*)')?[1]
    startDay: '2017-05-01'
    endDay: '2017-07-30'
    partialThreshold: 1
    completeThreshold: 99
    countThreshold: 0
    totalCount: 0
    messageOrHint: 'message'
    me: me
    serverConfig: serverConfig
    problemsByLevel: {}
    regexes: []
    otherRegexes: []
    displayMode: 'human-readable'
    showCampaigns: false
    showLevels: false
    showTranslated: true
    showUntranslated: true
    campaigns: []
    selectedCampaign: null
    selectedLevelSlugs: [_.last(location.href.split('/'))]
    loading: true
  computed:
    exportList: ->
      _(@problems).filter((p) =>
        p[@messageOrHint].length > 0 and\
          @percentDifference(p) < @completeThreshold and\
          (p.count / @totalCount) >= (@countThreshold / 100))
      .uniq((p) -> p.trimmed)
      .value()
    problems: ->
      _.sortBy(_.flatten(Object.values(@problemsByLevel), true), (p) -> -p.count)
  created: ->
    i18n.setLng(@language)
    @loadCampaigns()
    @loadLanguage(@language).then =>
      @setupRegexes()
      @getProblems(@levelSlug).then (newProblems) =>
        @compareStrings(newProblems)
        @loading = false
  watch:
    language: ->
      @loadLanguage(@language).then =>
        @setupRegexes()
        @compareStrings(@problems)
    selectedLevelSlugs: ->
      @loading = true
      promises = []
      for slug in @selectedLevelSlugs
        if not @problemsByLevel[slug]
          promises.push @getProblems(slug)
      Promise.all(promises).then (newProblems) =>
        @loading = false
        _.defer =>
          @compareStrings(_.flatten(newProblems))
    messageOrHint: ->
      @compareStrings(@problems)
  methods:
    loadLanguage: (language) ->
      new Promise (accept, reject) =>
        loading = application.moduleLoader.loadLanguage(language)
        if loading
          application.moduleLoader.once 'load-complete', accept
        else
          accept()
    loadCampaigns: ->
      $.get(
        '/db/campaign',
        (@campaigns) =>
          @selectedCampaign = _.find(@campaigns, (c) -> c.name is "Dungeon")
          for campaign in @campaigns
            Vue.set(campaign, 'levelsArray', Object.values(campaign.levels))
      )
    setupRegexes: ->
      en = require('locale/en').translation
      # Call require like this to prevent preload.js from trying to load app/locale.js which doesn't exist
      otherLang = window["require"]("locale/#{@language}").translation
      translationKeys = Object.keys(en.esper)
      @regexes = []
      for translationKey in translationKeys
        englishString = en.esper[translationKey]
        regex = Problem.prototype.makeTranslationRegex(englishString)
        @regexes.push(regex)
      @otherRegexes = []
      for translationKey in translationKeys
        otherString = otherLang.esper?[translationKey] or ''
        otherRegex = Problem.prototype.makeTranslationRegex(otherString)
        @otherRegexes.push(otherRegex)
    percentDifference: (problem) ->
      ((1 - problem.trimmed?.length / problem[@messageOrHint].length) * 100).toFixed(0)
    color: (problem) ->
      amountTranslated = @percentDifference(problem)
      if amountTranslated >= @completeThreshold
        return 'green'
      else if amountTranslated >= @partialThreshold
        return 'yellow'
      else
        return 'red'
    getProblemsAndCompare: (levelSlug) ->
      @getProblems(levelSlug).then (problems) =>
        @compareStrings(problems)
    getProblems: (levelSlug) ->
      new Promise (accept, reject) =>
        $.post(
          '/db/user.code.problem/-/common_problems',
          {startDay: @startDay, endDay: @endDay, slug: levelSlug},
          (newProblems) =>
            for problem in newProblems
              problem.hint ?= ''
            Vue.set(@problemsByLevel, levelSlug, newProblems)
            @totalCount = _.reduce(_.map(@problems, (p)->p.count), (a,b)->a+b)
            accept(newProblems)
        )
    compareStrings: (problems) ->
      $.i18n.setLng(@language)
      problems.forEach (problem) =>
        original = problem[@messageOrHint]
        translated = Problem.prototype.translate(problem[@messageOrHint])
        # distance = Levenshtein.get(_.last(original.split(':')), _.last(translated.split(':')))
        # trimmed = original
        # for regex in @regexes
        #   trimmed = trimmed.replace(regex, '')
        trimmed = translated
        for regex in @otherRegexes
          if false and /argument.*has.*a.*problem/.test(original)# and /Target.*an.*enemy.*variable/.test(regex.toString())
            console.log "===="
            console.log regex
            console.log trimmed
            console.log trimmed.replace(regex, '').replace(/^\n/, '')
            debugger if trimmed isnt trimmed.replace(regex, '').replace(/^\n/, '')
          trimmed = trimmed.replace(regex, '').replace(/^\n/, '')
        Vue.set(problem, 'translated', translated)
        # Vue.set(problem, 'distance', distance)
        Vue.set(problem, 'trimmed', trimmed)
    slugifyProblem: (problem) ->
      str = _.string.slugify(problem.trimmed)
      str.split('-').slice(0,4).join('_')

module.exports = class I18nVerifierView extends RootComponent
  id: 'i18n-verifier-view'
  template: require 'templates/base-flat'
  VueComponent: I18nVerifierComponent
  constructor: (options, @courseInstanceID) ->
    @propsData = { @courseInstanceID }
    super options
  destroy: ->
    super(arguments...)
    $.i18n.setLng(me.get('preferredLanguage'))

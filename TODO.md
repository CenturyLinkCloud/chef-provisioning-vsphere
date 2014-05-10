To Do Items
===========

Test framework
--------------

  - implement some form of test framework

Clone features
--------------

    :bootstrap_options
      :annotation
      :datastore_cluster
      :linked_clone

      :customization_options
        :spec
        :vlan
        :ips
        :dns_ips
        :dns_suffixes
        :gw
        :hostname
        :domain
        :tz
        :cpucount
        :memory

vApp features
-------------

  - create/start/stop/delete vApps in recipes
  - clone from existing vApp
  - replace machines in vApp

VM features
-----------

  - [:stop] with markAsTemplate

Usability
---------

  - create example cookbooks
  - with test-kitchen tests


Comments from jkeiser
---------------------

    brian_dupras_: could you re-send that suggestion you made for the vsphere provisioner.  I'm an idiot with irc and lost the my chat history before I got a chance to save off your comment.
    [1:25pm] jkeiser: Ah!  I was saying wrap the converge_by/start_server in an if statement that checks if the server needs to be started
    [1:25pm] jkeiser: When you say converge_by, you are causing two things:
    [1:26pm] jkeiser: 1. You print green text to the user that says "starting server X" or whatever you put in the description, making them thing the action actually happened
    [1:26pm] jkeiser: 2. You are setting a bit in the resource that says the update actually happened, so Chef will report that it has changed, send notifications that it's changed to other resources, etc.
    [1:26pm] jkeiser: So we only want to do that when something actually changes
    [1:26pm] jkeiser: It also does a third thing:
    [1:27pm] jkeiser: 3. if chef-client is run with --why-run, converge_by will print the green text saying what it WOULD do, but will not actually run the stuff in the block
    [1:27pm] jkeiser: So you can do a dry run on your stuff
    [1:27pm] jkeiser: er
    [1:27pm] jkeiser: s/converge_by/perform_action
    [1:28pm] jkeiser: I'll be offline for a bit, headed to a place that is not my house
    [1:28pm] brian_dupras_: great - thanks.  I'll make that change real soon.
    [1:28pm] brian_dupras_: And I'll not lose your comments this time.
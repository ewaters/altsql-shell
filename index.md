---
layout: page
title: Introducing AltSQL
tagline: A drop in replacement to the MySQL prompt
---
{% include JB/setup %}

AltSQL is a way to improve your user experience with `mysql`, `sqlite3`, `psql` and other tool that Perl has DBI drivers for. Currently written for MySQL only, the long term goal of this project is to provide users of the various SQL-based databases with a familiar command line interface but with modern improvements such as color, unicode box tables, and tweaks to the user interface that are fast and easy to prototype and experiment with.

### Quick Start

<pre class='altsql'>
$ sudo cpanm App::AltSQL
$ altsql -u root -h localhost -D sakila

Ctrl-C to reset the line; Ctrl-D to exit
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

altsql&gt; select * from actor limit 5
┏━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┓
┃ <span class='header_text'>actor_id</span> ┃ <span class='header_text'>first_name</span> ┃ <span class='header_text'>last_name</span>    ┃ <span class='header_text'>last_update</span>         ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━┩
│        <span class='cell_is_primary_key'>1</span> │ PENELOPE   │ GUINESS      │ 2006-02-15 04:34:33 │
│        <span class='cell_is_primary_key'>2</span> │ NICK       │ WAHLBERG     │ 2006-02-15 04:34:33 │
│        <span class='cell_is_primary_key'>3</span> │ ED         │ CHASE        │ 2006-02-15 04:34:33 │
│        <span class='cell_is_primary_key'>4</span> │ JENNIFER   │ DAVIS        │ 2006-02-15 04:34:33 │
│        <span class='cell_is_primary_key'>5</span> │ JOHNNY     │ LOLLOBRIGIDA │ 2006-02-15 04:34:33 │
└──────────┴────────────┴──────────────┴─────────────────────┘
5 rows in set (0.00 sec)

altsql&gt;
</pre>

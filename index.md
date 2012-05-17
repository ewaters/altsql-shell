---
layout: page
title: Introducing AltSQL
tagline: A drop in replacement to the MySQL prompt
---
{% include JB/setup %}

AltSQL is a way to improve your user experience with `mysql`, `sqlite3`, `psql` and other tool that Perl has DBI drivers for. Currently written for MySQL only, the long term goal of this project is to provide users of the various SQL-based databases with a familiar command line interface but with modern improvements such as color, unicode box tables, and tweaks to the user interface that are fast and easy to prototype and experiment with.

### Quick Start

<pre>
$ sudo cpanm App::AltSQL
</pre>

Now you can use it just like the `mysql` prompt.

<pre class='altsql'>
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

### Reasoning

There are a few key issues that this programmer has had with using the mysql client every day. After looking for alternatives and other ways to fix the problems, reimplementing the client in Perl seemed like the easiest approach, and lent towards the greatest possible adoption by my peers. Here are a few of those issues:

#### Ctrl-C kills the program

   All of the shells that we used on a daily basis allow you to abandon the half-written statement on the prompt by typing Ctrl-C. Spending all day in shells, you expect this behavior to be consistent, but you do this in mysql and you will be thrown to the street. Let's do what I mean, and abandon the statement.

#### Wide output wraps

  We are grateful that mysql at least uses ASCII art for table formatting (unlike sqlite3 for some reason). But there are some tables that I work with that have many columns, with long names (it's often easier to keep adding columns to a table over time). As a result, when you perform a simple `select * from fim limit 4` you quickly find your terminal overwhelmed by useless ASCII art attempting (and mostly failing) to provide any semblance of meaning from the result. You can throw a '\G' onto the command, but if it took 10 seconds to execute and you locked tables while doing it, you could be slowing down your website or letting your slave fall behind on sync.

 Suffice it to say, it's a much better experience if, just like with git diff, wide output is left wide, and you are optionally able to scroll horizontally with your arrow keys like you wanted in the first place.

#### Color

  Most other modern programs we developers use on a daily basis (vim, ls, top, git, tmux, screen) offer to provide additional context to you via color. By consistently setting colors on a variable type or file type, programs can convey to us additional context that allows us to better grasp and understand what's happening. They help us be smarter and faster at our jobs, and detect when we've made a mistake. There's no reason we shouldn't use color to make it obvious which column(s) form the primary key of a table, or which columns are a number type or string type. The DBI statement handler contains lots of context, and we can interrogate the information_schema tables in mysql for even more.

#### Unicode Box characters

  The usage of '|', '+' and '-' for drawing tables and formatting data seems a bit antiquated. Other tools are adopting Unicode characters, and most programmers are now using terminal programs that support Unicode and UTF8 encoding natively. The Unicode box symbol set allows seamless box drawing which allows you to read between the lines, so to speak. It is less obtrusive, and combining this with color you can create a more useful and clear user experience.

I've thought of a number of other features, but so too have my coworkers and friends. Most people I've spoken with have ideas for future features. Next time you're using your DB shell and find yourself irritated at a feature or bug in the software that you feel could be done much better, file a feature request or, better yet, write your own plugins.

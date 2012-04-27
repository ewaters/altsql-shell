# Annoyances with mysql, fixed!

 * Ctrl-C doesn't kill the program; it just terminates the command

 * Multiline input in mysql is treated as multiple lines of history; it's very hard to use your history buffer after executing a multiline statement.  Additionally, you can't edit lines above the current one in a multiline statement


## show create table

```
mysql> show create table tradeshows;
+------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table      | Create Table                                                                                                                                                                                                                                                                                                                                                                    |
+------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| tradeshows | CREATE TABLE `tradeshows` (
`id` int(10) unsigned NOT NULL auto_increment,
`name` varchar(255) NOT NULL,
`start_time` datetime NOT NULL,
`end_time` datetime NOT NULL,
`create_time` datetime NOT NULL,
`giveaway_product_id` int(10) unsigned NOT NULL,
PRIMARY KEY  (`id`),
UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=41 DEFAULT CHARSET=utf8 | 
+------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)
```

Normally, this comman will be rendered in a table.  This is not useful.  Instead, let's just spit out the Create Table column of the result without any table markup.

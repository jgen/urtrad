
------------------------------------------------------------------------

             Remote Interface for Urban Terror 4.1

    Date:     July/August 2009
    Version:  0.1a  (Alpha release)
    Author:   Jeff Genovy (jgen)


    This project is released under a BSD style license.
    ( see LICENSE.txt file for details )


    Description:
        Administrative tool for assisting in monitoring Urban Terror
        servers. Provides a web interface to allow easy/effective use.

    Files:

        rcon.pl
            - Backend monitoring script.
            - Watches the Urban Terror server and feeds info/stats
              into the database.

        index.html
            - Front end web interface.

        remoteinterface.js
            - Uses the YUI library to build up the GUI from index.html

        interface.php
            - Interface layer between web front end and database.

        setup.php
            - Setup script that will create the database tables and the config
              file that is shared between interface.php & rcon.pl

        config.php
            - Functions/variables for writing the database config file

        functions.php
            - Functions for reading in the sql file

        radmode_database.sql
            - SQL to create database tables.

        -- Not Used / Required --

        radmode_database_sqlite.sql
            - SQL to create database for SQLite

        urtvars.pl
            - Additional variables for parsing log files.


------------------------------------------------------------------------


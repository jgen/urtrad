
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
        index.html
            - Front end web interface.
            - Uses the YUI library & other JavaScript components from
              the resource subdirectory.

        rcon.pl
            - Backend monitoring script.
            - Watches the Urban Terror server and feeds info/stats
              into the database.

        interface.php
            - Interface layer between web front end and database.

        radmode_database.sql
            - SQL to create database tables.

        urtvars.pl
            - Additional variables for parsing log files.


------------------------------------------------------------------------


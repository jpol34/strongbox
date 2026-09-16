if (-not ([System.Management.Automation.PSTypeName] 'Strongbox.Sqlite.Helper').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Strongbox.Sqlite
{
    // System.Data.SQLite (PSSQLite) only ships native binaries for win/osx/linux-x64 - no
    // linux-arm64 - so this P/Invokes libsqlite3 directly. That .so ships for every architecture
    // the platform's package manager supports (installed via apt in the Dockerfile), so this
    // works identically on amd64 and arm64 without a per-arch native dependency to track.
    internal static class Native
    {
        private const string Lib = "libsqlite3.so.0";
        private const int SQLITE_OK = 0;

        public delegate int ExecCallback(IntPtr arg, int argc, IntPtr argv, IntPtr colNames);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_open([MarshalAs(UnmanagedType.LPUTF8Str)] string filename, out IntPtr db);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_close(IntPtr db);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_exec(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, ExecCallback callback, IntPtr arg, out IntPtr errmsg);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void sqlite3_free(IntPtr ptr);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_prepare_v2(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, int nBytes, out IntPtr stmt, out IntPtr tail);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_bind_parameter_index(IntPtr stmt, [MarshalAs(UnmanagedType.LPUTF8Str)] string name);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_bind_text(IntPtr stmt, int index, [MarshalAs(UnmanagedType.LPUTF8Str)] string val, int n, IntPtr destructor);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_bind_int64(IntPtr stmt, int index, long val);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_bind_null(IntPtr stmt, int index);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_step(IntPtr stmt);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_column_count(IntPtr stmt);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr sqlite3_column_name(IntPtr stmt, int i);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr sqlite3_column_text(IntPtr stmt, int i);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sqlite3_finalize(IntPtr stmt);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr sqlite3_errmsg(IntPtr db);
    }

    // Handle returned to PowerShell by New-SQLiteConnection - Put-Blob.ps1 keeps this open across
    // several Invoke-SqliteQuery calls to hold a single BEGIN IMMEDIATE/COMMIT transaction.
    public sealed class Connection
    {
        public IntPtr Handle;
        public void Close()
        {
            Helper.Close(Handle);
            Handle = IntPtr.Zero;
        }
    }

    public static class Helper
    {
        private const int SQLITE_OK = 0;
        private const int SQLITE_ROW = 100;
        private const int SQLITE_DONE = 101;

        public static IntPtr Open(string path)
        {
            IntPtr db;
            int rc = Native.sqlite3_open(path, out db);
            if (rc != SQLITE_OK)
            {
                string msg = db != IntPtr.Zero ? Marshal.PtrToStringUTF8(Native.sqlite3_errmsg(db)) : "unknown sqlite error";
                if (db != IntPtr.Zero) { Native.sqlite3_close(db); }
                throw new InvalidOperationException("sqlite3_open failed: " + msg);
            }
            return db;
        }

        public static void Close(IntPtr db)
        {
            if (db != IntPtr.Zero) { Native.sqlite3_close(db); }
        }

        // Handles PRAGMA/DDL/transaction-control statements, including multiple ';'-separated
        // statements in one call (sqlite3_exec runs each in turn) - used whenever the caller
        // passes no parameters, since none of those call sites need bind-parameter safety.
        public static List<Dictionary<string, object>> ExecuteNonQuery(IntPtr db, string sql)
        {
            var rows = new List<Dictionary<string, object>>();
            Native.ExecCallback cb = (arg, argc, argv, colNames) =>
            {
                var row = new Dictionary<string, object>();
                for (int i = 0; i < argc; i++)
                {
                    IntPtr namePtr = Marshal.ReadIntPtr(colNames, i * IntPtr.Size);
                    IntPtr valPtr = Marshal.ReadIntPtr(argv, i * IntPtr.Size);
                    string name = Marshal.PtrToStringUTF8(namePtr);
                    object val = valPtr == IntPtr.Zero ? null : (object)Marshal.PtrToStringUTF8(valPtr);
                    row[name] = val;
                }
                rows.Add(row);
                return 0;
            };
            IntPtr errmsg;
            int rc = Native.sqlite3_exec(db, sql, cb, IntPtr.Zero, out errmsg);
            if (rc != SQLITE_OK)
            {
                string msg = errmsg != IntPtr.Zero ? Marshal.PtrToStringUTF8(errmsg) : "unknown sqlite error";
                if (errmsg != IntPtr.Zero) { Native.sqlite3_free(errmsg); }
                throw new InvalidOperationException("sqlite3_exec failed: " + msg);
            }
            return rows;
        }

        // Single-statement parameterized query/exec - covers every SELECT/INSERT/UPDATE/DELETE
        // in the storage layer that binds @name/@scope/... values.
        public static List<Dictionary<string, object>> ExecuteQuery(IntPtr db, string sql, IDictionary parameters)
        {
            IntPtr stmt, tail;
            int rc = Native.sqlite3_prepare_v2(db, sql, -1, out stmt, out tail);
            if (rc != SQLITE_OK)
            {
                throw new InvalidOperationException("sqlite3_prepare_v2 failed: " + Marshal.PtrToStringUTF8(Native.sqlite3_errmsg(db)));
            }
            try
            {
                if (parameters != null)
                {
                    foreach (DictionaryEntry entry in parameters)
                    {
                        string paramName = "@" + entry.Key;
                        int idx = Native.sqlite3_bind_parameter_index(stmt, paramName);
                        if (idx == 0) { continue; }
                        object value = entry.Value;
                        if (value == null)
                        {
                            Native.sqlite3_bind_null(stmt, idx);
                        }
                        else if (value is int || value is long)
                        {
                            Native.sqlite3_bind_int64(stmt, idx, Convert.ToInt64(value));
                        }
                        else
                        {
                            Native.sqlite3_bind_text(stmt, idx, value.ToString(), -1, new IntPtr(-1));
                        }
                    }
                }

                var rows = new List<Dictionary<string, object>>();
                int stepRc;
                while ((stepRc = Native.sqlite3_step(stmt)) == SQLITE_ROW)
                {
                    int colCount = Native.sqlite3_column_count(stmt);
                    var row = new Dictionary<string, object>();
                    for (int i = 0; i < colCount; i++)
                    {
                        string name = Marshal.PtrToStringUTF8(Native.sqlite3_column_name(stmt, i));
                        IntPtr valPtr = Native.sqlite3_column_text(stmt, i);
                        object val = valPtr == IntPtr.Zero ? null : (object)Marshal.PtrToStringUTF8(valPtr);
                        row[name] = val;
                    }
                    rows.Add(row);
                }
                if (stepRc != SQLITE_DONE)
                {
                    throw new InvalidOperationException("sqlite3_step failed: " + Marshal.PtrToStringUTF8(Native.sqlite3_errmsg(db)));
                }
                return rows;
            }
            finally
            {
                Native.sqlite3_finalize(stmt);
            }
        }
    }
}
'@
}

function New-SQLiteConnection {
    <#
    .SYNOPSIS
        Opens a SQLite database handle that stays open across several Invoke-SqliteQuery calls -
        used by Put-Blob's BEGIN IMMEDIATE/COMMIT transaction.
    #>
    param([Parameter(Mandatory)][string] $DataSource)
    $conn = [Strongbox.Sqlite.Connection]::new()
    $conn.Handle = [Strongbox.Sqlite.Helper]::Open($DataSource)
    return $conn
}

import java.sql.*;
import java.io.*;
import java.util.*;

public class Sample {

    private static final String PASSWORD = "hardcoded_password_123";
    private static final String SECRET_KEY = "sk-abcdef1234567890";

    public void sqlInjection(Connection conn, String userId) throws SQLException {
        Statement stmt = conn.createStatement();
        stmt.execute("SELECT * FROM users WHERE id = '" + userId + "'");
    }

    public void genericExceptionCatch() {
        try {
            riskyOperation();
        } catch (Exception e) {
            // swallowed
        }
    }

    public void emptyExceptionCatch() {
        try {
            riskyOperation();
        } catch (IOException e) {
        }
    }

    public Object nullReturn() {
        return null;
    }

    public void systemExit() {
        System.exit(1);
    }

    public void deeplyNested(int[][][] data) {
        for (int i = 0; i < data.length; i++) {
            if (data[i] != null) {
                for (int j = 0; j < data[i].length; j++) {
                    if (data[i][j] != null) {
                        for (int k = 0; k < data[i][j].length; k++) {
                            if (data[i][j][k] > 0) {
                                System.out.println(data[i][j][k]);
                            }
                        }
                    }
                }
            }
        }
    }

    // TODO: refactor this method
    // FIXME: handle edge case

    public String stringConcatInLoop(List<String> items) {
        String result = "";
        for (String item : items) {
            result += item + ",";
        }
        return result;
    }

    public void veryLongMethod(int x) {
        int a = x + 1;
        int b = x + 2;
        int c = x + 3;
        int d = x + 4;
        int e = x + 5;
        int f = x + 6;
        int g = x + 7;
        int h = x + 8;
        int i = x + 9;
        int j = x + 10;
        int k = x + 11;
        int l = x + 12;
        int m = x + 13;
        int n = x + 14;
        int o = x + 15;
        int p = x + 16;
        int q = x + 17;
        int r = x + 18;
        int s = x + 19;
        int t = x + 20;
        int u = x + 21;
        int v = x + 22;
        int w = x + 23;
        int y = x + 24;
        int z = x + 25;
        int aa = x + 26;
        int bb = x + 27;
        int cc = x + 28;
        int dd = x + 29;
        int ee = x + 30;
        int ff = x + 31;
        int gg = x + 32;
        int hh = x + 33;
        int ii = x + 34;
        int jj = x + 35;
        int kk = x + 36;
        int ll = x + 37;
        int mm = x + 38;
        int nn = x + 39;
        int oo = x + 40;
        int pp = x + 41;
        int qq = x + 42;
        int rr = x + 43;
        int ss = x + 44;
        int tt = x + 45;
        int uu = x + 46;
        int vv = x + 47;
        int ww = x + 48;
        int xx = x + 49;
        int yy = x + 50;
        int zz = x + 51;
        System.out.println(zz);
    }

    private void riskyOperation() throws IOException {
        throw new IOException("error");
    }
}

package org.firetvcontroller.remote;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/** Keeps Android's existing, authorized input command warm on its ADB shell. */
public final class FastRemote {
    private static final String ALLOWED_KEYS = ",0,3,4,19,20,21,22,23,66,82,85,";

    public static void main(String[] args) throws Exception {
        Method input = Class.forName("com.android.commands.input.Input")
                .getMethod("main", String[].class);
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        // Initialise the Android input command before accepting navigation.
        input.invoke(null, (Object) new String[] {"keyevent", "0"});
        System.out.println("FIRETV_READY_2");
        System.out.flush();
        String line;
        while ((line = reader.readLine()) != null) {
            if (line.equals("Q")) break;
            try {
                if (line.equals("P")) {
                    // Ping the existing stream without changing anything on the TV.
                } else if (line.startsWith("K ")) {
                    String key = line.substring(2);
                    if (!key.matches("[0-9]{1,2}") || !ALLOWED_KEYS.contains("," + key + ",")) throw new IllegalArgumentException();
                    input.invoke(null, (Object) new String[] {"keyevent", key});
                } else if (line.startsWith("T ")) {
                    String text = new String(Base64.getDecoder().decode(line.substring(2)), StandardCharsets.UTF_8);
                    if (text.length() > 500 || !text.matches("[ -~]*")) throw new IllegalArgumentException();
                    // The original Android command translates %s into spaces.
                    // Split a literal %s, passing text as arguments (not shell code).
                    int start = 0;
                    int split;
                    while ((split = text.indexOf("%s", start)) != -1) {
                        input.invoke(null, (Object) new String[] {"text", text.substring(start, split + 1)});
                        start = split + 1;
                    }
                    if (start < text.length()) input.invoke(null, (Object) new String[] {"text", text.substring(start)});
                } else throw new IllegalArgumentException();
                System.out.println("FIRETV_OK");
            } catch (Exception exception) {
                System.out.println("FIRETV_ERROR");
            }
            System.out.flush();
        }
    }
}

import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.SSLParameters;
import java.io.*;

public class SslTest {
	public static void main(String[] args) throws Exception {
		/* Use HTTPS verification algorithm, which checks hostname validty for us */
		SSLParameters sslParams = new SSLParameters();
		sslParams.setEndpointIdentificationAlgorithm("HTTPS");

		try (
			SSLSocket sslSocket = (SSLSocket) SSLSocketFactory.getDefault().createSocket(args[0], Integer.parseInt(args[1]));
			InputStream in = sslSocket.getInputStream();
			OutputStream out = sslSocket.getOutputStream();
		    ) {
			sslSocket.setSSLParameters(sslParams);

			out.write(1);

			while (in.available() > 0) {
				System.out.print(in.read());
			}
		    }
	}
}

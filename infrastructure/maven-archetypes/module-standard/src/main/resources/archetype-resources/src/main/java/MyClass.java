#set( $symbol_pound = '#' )
#set( $symbol_dollar = '$' )
#set( $symbol_escape = '\' )
package ${package};

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * MyClass
 * 
 * @since 1.0.0
 */
public class MyClass {
	
	final static Logger logger = LoggerFactory.getLogger(MyClass.class);

	public static void main(String args[]) {
		
		logger.info("This is a log message!!!");
		
	}
	
}

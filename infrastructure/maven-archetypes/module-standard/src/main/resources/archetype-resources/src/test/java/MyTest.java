/*******************************************************************************
 * Copyright 2020 Marcelo Riss
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *******************************************************************************/
#set( $symbol_pound = '#' )
#set( $symbol_dollar = '$' )
#set( $symbol_escape = '\' )
package ${package};

import org.junit.AfterClass;
import org.junit.BeforeClass;
import org.junit.Test;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


/**
 * MyTest
 * 
 * @since 1.0.0
 */
public class MyTest {
	
	final static Logger logger = LoggerFactory.getLogger(MyTest.class);

	@BeforeClass
	public static void setUp() throws Exception {
		logger.info("This is a log message!!!");
	}
	
	@AfterClass
	public static void tearDown() throws Exception{
		logger.info("This is a log message!!!");
	}

	@Test
	public void testSomething() throws Exception {
		logger.info("This is a log message!!!");
		MyClass.main(new String[]{"arg1", "arg2"});		
	}

}
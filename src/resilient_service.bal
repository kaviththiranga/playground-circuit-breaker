import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/time;

json previousRes;

endpoint http:ServiceEndpoint listener {
    port:9090
};

// Endpoint with circuit breaker(CB) can short circuit responses
// under some conditions. Circuit flips to OPEN state when
// errors or responses take longer than timeout.
// OPEN circuits bypass endpoint and return error.
endpoint http:ClientEndpoint legacyServiceResilientEP {
    circuitBreaker: {

                    // failures allowed
                        failureThreshold:0,

                    // reset circuit to CLOSED state after timeout
                        resetTimeout:3000,

                    // error codes that open the circuit
                        statusCodes:[400, 404, 500]
                    },

// URI of the remote service
    targets: [{ url: "http://localhost:9095"}],

// Invocation timeout - independent of circuit
    endpointTimeout:6000
};


@http:ServiceConfig {basePath:"/resilient/time"}
service<http:Service> timeInfo bind listener {

    @http:ResourceConfig {
        methods:["GET"],
        path:"/"
    }
    getTime (endpoint caller, http:Request req) {

        var response = legacyServiceResilientEP
                       -> get("/legacy/localtime", {});

        // Match response for successful or failed messages.
        match response {

        // Circuit breaker not tripped, process response
            http:Response res => {
                if (res.statusCode == 200) {
                    io:println(" >> CB : CLOSE - " +
                        " Remote service is invoked successfully. "
                               );
                    previousRes =? res.getJsonPayload();
                } else {
                    // Remote endpoint returns and error.
                    io:println(" >> Error message received"
                     + " from remote service");
                }
                _ = caller -> forward(res);
            }

        // Circuit breaker tripped and generates error
            http:HttpConnectorError err => {
                http:Response errResponse = {};
                io:println(" >> CB: OPEN -"
                       + "Remote service invocation is suspended!");

                // Inform client service is unavailable
                errResponse.statusCode = 503;

                // Use the last successful response
                json errJ = { CACHED_RESPONSE:previousRes };
                errResponse.setJsonPayload(errJ);
                _ = caller -> respond(errResponse);
            }
        }
    }
}




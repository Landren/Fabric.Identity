﻿using System.Collections.Generic;
using System.Net;
using Fabric.Identity.API.Exceptions;
using Fabric.Identity.API.Models;
using Fabric.Identity.API.Persistence;
using Fabric.Identity.API.Validation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Serilog;
using Swashbuckle.AspNetCore.Annotations;
using IS4 = IdentityServer4.Models;

namespace Fabric.Identity.API.Management
{
    /// <summary>
    ///     Manage client applications.
    /// </summary>
    [Authorize(Policy = FabricIdentityConstants.AuthorizationPolicyNames.RegistrationThreshold,
        AuthenticationSchemes = "Bearer")]
    [ApiVersion("1.0")]
    [Route("api/client")]
    [Route("api/v{version:apiVersion}/client")]
    public class ClientController : BaseController<IS4.Client>
    {
        private const string NotFoundErrorMsg = "The specified client id could not be found.";
        private readonly IClientManagementStore _clientManagementStore;

        /// <summary>
        ///     Manage client applications (aka relying parties) in Fabric.Identity.
        /// </summary>
        /// <param name="clientManagementStore">IClientManagementStore</param>
        /// <param name="validator"></param>
        /// <param name="logger"></param>
        public ClientController(IClientManagementStore clientManagementStore, ClientValidator validator, ILogger logger)
            : base(validator, logger)
        {
            _clientManagementStore = clientManagementStore;
        }

        /// <summary>
        ///     Find a client by id
        /// </summary>
        /// <param name="id">The unique identifier of the client.</param>
        /// <returns></returns>
        [HttpGet("{id}")]
        [SwaggerResponse(200, "Success", typeof(Client))]
        [SwaggerResponse(404, NotFoundErrorMsg, typeof(Error))]
        [SwaggerResponse(400, BadRequestErrorMsg, typeof(Error))]
        public IActionResult Get(string id)
        {
            var client = _clientManagementStore.FindClientByIdAsync(id).Result;

            if (string.IsNullOrEmpty(client?.ClientId))
            {
                return CreateFailureResponse($"The specified client with id: {id} was not found",
                    HttpStatusCode.NotFound);
            }

            return Ok(client.ToClientViewModel());
        }

        /// <summary>
        ///     Reset a client secret
        /// </summary>
        /// <param name="id">The unique id of the client to reset.</param>
        /// <returns></returns>
        [HttpPost("{id}/resetPassword")]
        [SwaggerResponse(200, "The secret for the client has been reset.", typeof(Client))]
        [SwaggerResponse(404, NotFoundErrorMsg, typeof(Error))]
        [SwaggerResponse(400, BadRequestErrorMsg, typeof(Error))]
        public IActionResult ResetPassword(string id)
        {
            var client = _clientManagementStore.FindClientByIdAsync(id).Result;

            if (string.IsNullOrEmpty(client?.ClientId))
            {
                return CreateFailureResponse($"The specified client with id: {id} was not found",
                    HttpStatusCode.NotFound);
            }

            // Update password
            var newPassword = GeneratePassword();
            client.ClientSecrets = new List<IS4.Secret> {GetNewSecret(newPassword)};
            _clientManagementStore.UpdateClient(id, client);

            // Prepare return values
            var viewClient = client.ToClientViewModel();
            viewClient.ClientSecret = newPassword;

            return Ok(viewClient);
        }

        /// <summary>
        ///     Add a client
        /// </summary>
        /// <param name="client">The <see cref="IS4.Client" /> object to add.</param>
        /// <returns></returns>
        [HttpPost]
        [SwaggerResponse(201, "The client was created.", typeof(Client))]
        [SwaggerResponse(400, BadRequestErrorMsg, typeof(Error))]
        [SwaggerResponse(409, DuplicateErrorMsg, typeof(Error))]
        public IActionResult Post([FromBody] Client client)
        {
            try
            {
                var is4Client = client.ToIs4ClientModel();
                return ValidateAndExecute(is4Client, () =>
                {
                    var id = is4Client.ClientId;

                    // override any secret in the request.
                    var clientSecret = GeneratePassword();
                    is4Client.ClientSecrets =
                        new List<IS4.Secret> {GetNewSecret(clientSecret)};
                    _clientManagementStore.AddClient(is4Client);

                    var viewClient = is4Client.ToClientViewModel();
                    viewClient.ClientSecret = clientSecret;

                    return CreatedAtAction("Get", new {id}, viewClient);
                }, $"{FabricIdentityConstants.ValidationRuleSets.ClientPost},{FabricIdentityConstants.ValidationRuleSets.Default}");
            }
            catch (BadRequestException<Client> ex)
            {
                return CreateFailureResponse(ex.Message, HttpStatusCode.BadRequest);
            }
        }

        /// <summary>
        ///     Update a client
        /// </summary>
        /// <param name="id">The unique id of the client to update.</param>
        /// <param name="client">The <see cref="IS4.Client" /> object to update.</param>
        /// <returns></returns>
        [HttpPut("{id}")]
        [SwaggerResponse(204, "The specified client was updated.", typeof(void))]
        [SwaggerResponse(404, NotFoundErrorMsg, typeof(Error))]
        [SwaggerResponse(400, BadRequestErrorMsg, typeof(Error))]
        [SwaggerResponse(409, DuplicateErrorMsg, typeof(Error))]
        public IActionResult Put(string id, [FromBody] Client client)
        {
            var is4Client = client.ToIs4ClientModel();

            return ValidateAndExecute(is4Client, () =>
            {
                if (!string.Equals(id, client.ClientId))
                {
                    return CreateFailureResponse(
                        "The ClientId in the request URL path must match the ClientId in the request body.", HttpStatusCode.BadRequest);
                }

                var storedClient = _clientManagementStore.FindClientByIdAsync(id).Result;

                if (string.IsNullOrEmpty(storedClient?.ClientId))
                {
                    return CreateFailureResponse($"The specified client with id: {id} was not found",
                        HttpStatusCode.NotFound);
                }

                // Prevent from changing secrets.
                is4Client.ClientSecrets = storedClient.ClientSecrets;
                // Prevent from changing payload ClientId.
                is4Client.ClientId = id;

                _clientManagementStore.UpdateClient(id, is4Client);
                return NoContent();
            });
        }

        /// <summary>
        ///     Delete a client
        /// </summary>
        /// <param name="id">The unique id of the client to delete.</param>
        /// <returns></returns>
        [HttpDelete("{id}")]
        [SwaggerResponse(204, "The specified client was deleted.", typeof(void))]
        [SwaggerResponse(404, NotFoundErrorMsg, typeof(Error))]
        public IActionResult Delete(string id)
        {
            var client = _clientManagementStore.FindClientByIdAsync(id).Result;

            if (string.IsNullOrEmpty(client?.ClientId))
            {
                return CreateFailureResponse($"The specified client with id: {id} was not found",
                    HttpStatusCode.NotFound);
            }

            _clientManagementStore.DeleteClient(id);
            return NoContent();
        }
    }
}
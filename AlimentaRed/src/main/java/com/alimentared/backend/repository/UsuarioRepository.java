package com.alimentared.backend.repository;

import com.alimentared.backend.entity.Usuario;
import com.alimentared.backend.entity.enums.Rol;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface UsuarioRepository extends JpaRepository<Usuario, Long> {

    @EntityGraph(attributePaths = "organizacion")
    Optional<Usuario> findWithOrganizacionByCorreoIgnoreCase(String correo);

    @EntityGraph(attributePaths = "organizacion")
    Optional<Usuario> findWithOrganizacionByIdUsuario(Long idUsuario);

    Optional<Usuario> findByCorreoIgnoreCase(String correo);

    Optional<Usuario> findByOrganizacion_IdOrganizacion(Long idOrganizacion);

    boolean existsByCorreoIgnoreCase(String correo);

    boolean existsByRol(Rol rol);
}

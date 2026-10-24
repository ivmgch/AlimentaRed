package com.example.AlimentaRed.Entity;

import com.example.AlimentaRed.Entity.Enum.Rol;
import jakarta.persistence.*;
import lombok.Data;

    @Data
    @Entity
    @Table(name = "usuario")

    public class Usuario {

        @Id
        @GeneratedValue(strategy = GenerationType.IDENTITY)
        private Long idUsuario;

        @Enumerated(EnumType.STRING)
        @Column(nullable = false)
        private Rol rol;

        @OneToOne(fetch = FetchType.LAZY)
        @JoinColumn(name = "organizacion_id", unique = true)
        private Organizacion organizacion;


        @Column(nullable = false)
        private String contrasena;
    }

